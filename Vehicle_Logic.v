module Vehicle_Logic (
    input clk, input rst,
    input engine_on,
    input tick_1sec, input tick_speed,
    input [3:0] current_gear, // 3:P, 6:R, 9:N, 12:D
    input [7:0] adc_accel,
    input is_brake_normal, input is_brake_hard,
    
    output reg [7:0] speed = 0,
    output reg [13:0] rpm = 0,
    output reg [7:0] fuel = 100,
    output reg [7:0] temp = 25,      // 초기 온도: 상온 25도
    output reg [31:0] odometer_raw = 0, // 총 주행 거리 (단위: 미터)
    output reg ess_trigger = 0
);
    parameter IDLE_RPM = 800;
    
    // 물리 연산을 위한 변수
    reg [9:0] power;      // 엔진 힘
    reg [9:0] resistance; // 공기/바닥 저항
    
    // [개선] 불감대(Dead Zone) 적용: 노이즈 제거
    wire [7:0] effective_accel;
    assign effective_accel = (adc_accel > 50) ? (adc_accel - 50) : 8'd0;

    // 계산용 임시 변수
    reg [13:0] calc_rpm; 

    // =========================================================
    // 1. 물리 엔진 (속도 및 가속도 제어)
    // =========================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin 
            speed <= 0;
            ess_trigger <= 0; 
        end
        else if (!engine_on) begin 
            speed <= 0; 
            ess_trigger <= 0;
        end
        else if (tick_speed) begin
            // A. 힘(Power) 계산
            if (current_gear == 4'd12) power = effective_accel;       // D: 100%
            else if (current_gear == 4'd6) power = effective_accel / 2; // R: 50%
            else power = 0; // P, N: 동력 전달 안됨

            // B. 저항(Resistance) 계산 (속도가 빠를수록 저항 증가)
            resistance = speed + 5;

            // C. 속도 갱신 로직
            if (is_brake_hard) begin 
                // 급브레이크 (고속 밀림 현상 구현)
                if (speed > 150) begin
                    if(speed >= 2) speed <= speed - 2; else speed <= 0;
                end else if (speed > 80) begin
                    if(speed >= 4) speed <= speed - 4; else speed <= 0;
                end else begin
                    if(speed >= 8) speed <= speed - 8; else speed <= 0;
                end
                
                // 급제동 경보(ESS) 트리거 (50km/h 이상에서 급정거 시)
                if(speed > 50) ess_trigger <= 1;
                else ess_trigger <= 0;
            end 
            else if (is_brake_normal) begin 
                // 일반 브레이크
                if (speed > 150) begin
                    if(speed >= 1) speed <= speed - 1; else speed <= 0;
                end else if (speed > 80) begin
                    if(speed >= 2) speed <= speed - 2; else speed <= 0;
                end else begin
                    if(speed >= 3) speed <= speed - 3; else speed <= 0;
                end
                ess_trigger <= 0;
            end 
            else begin 
                // 악셀링 또는 관성 주행
                ess_trigger <= 0;
                
                // 가속 (Power > Resistance)
                if (power > resistance) begin
                    // 후진 속도 제한 (50km/h)
                    if (current_gear == 4'd6 && speed >= 50) begin
                        // 가속 불가
                    end else if (speed < 250) begin
                        speed <= speed + 1;
                    end
                end 
                // 자연 감속 (Power < Resistance)
                else if (power < resistance) begin
                    if (speed > 0) speed <= speed - 1;
                end
            end
        end
    end

    // =========================================================
    // 2. RPM 계산 (P/N 리미터 및 6단 자동 변속 시뮬레이션)
    // =========================================================
    always @(*) begin
        if (!engine_on) rpm = 0;
        
        // --- [수정] P, N 상태 (공회전) ---
        else if (current_gear == 4'd3 || current_gear == 4'd9) begin 
            // 가상 RPM 계산
            calc_rpm = IDLE_RPM + (effective_accel * 20);
            
            // [Rev Limiter] P단 풀악셀 시 엔진 보호를 위해 4000 RPM 제한
            if (calc_rpm > 4000) rpm = 4000;
            else rpm = calc_rpm;
        end
        
        // --- D, R 상태 (주행 중) ---
        else begin 
            // 속도 대역별 기어비 시뮬레이션
            if (speed < 40)       rpm = IDLE_RPM + (speed * 100);       // 1단
            else if (speed < 80)  rpm = 1500 + ((speed - 40) * 80);     // 2단
            else if (speed < 120) rpm = 1500 + ((speed - 80) * 60);     // 3단
            else if (speed < 160) rpm = 1600 + ((speed - 120) * 50);    // 4단
            else if (speed < 200) rpm = 1700 + ((speed - 160) * 40);    // 5단
            else                  rpm = 1800 + ((speed - 200) * 30);    // 6단
            
            // 주행 중 레드존 제한 (8000 RPM)
            if (rpm > 8000) rpm = 8000;
        end
    end

    // =========================================================
    // 3. OBD 데이터 (연료, 온도, 거리) - [현실적 물리 적용]
    // =========================================================
    reg [1:0] fuel_timer;
    reg [2:0] temp_timer;     // 온도 변화 속도 조절용
    reg [15:0] dist_cm_acc;   // 거리 정밀 계산용 (cm 단위 누적)

    always @(posedge clk or posedge rst) begin
        if (rst) begin 
            fuel <= 100;
            temp <= 25;       // 초기값: 상온 25도
            odometer_raw <= 0; 
            fuel_timer <= 0;
            temp_timer <= 0;
            dist_cm_acc <= 0;
        end
        else if (tick_1sec) begin
            
            // --- [A. 거리 계산 로직 (Physics Based)] ---
            // 공식: 1 km/h = 초당 약 27.77cm 이동
            // 1초마다 (현재속도 * 28)cm 만큼 이동했다고 가정
            if (engine_on && speed > 0) begin
                dist_cm_acc <= dist_cm_acc + (speed * 28);
                
                // 100cm(1m)가 쌓이면 미터기(odometer) +1 증가
                if (dist_cm_acc >= 100) begin
                    odometer_raw <= odometer_raw + (dist_cm_acc / 100);
                    dist_cm_acc <= dist_cm_acc % 100;
                end
            end

            // --- [B. 연료 소비 로직] ---
            if (engine_on && (speed > 0 || rpm > 1000)) begin
                if (fuel_timer >= 2) begin // 약 3초마다 1% 감소
                    if (fuel > 0) fuel <= fuel - 1;
                    fuel_timer <= 0;
                end else begin
                    fuel_timer <= fuel_timer + 1;
                end
            end

            // --- [C. 엔진 온도 로직 (Thermostat Simulation)] ---
            // 엔진은 90도(적정 온도)를 유지하려 하고, RPM이 높으면 과열됨
            if (engine_on) begin
                if (temp_timer >= 1) begin // 2초마다 갱신
                    temp_timer <= 0;
                    
                    if (rpm > 5000) begin
                        // [과열 구간] 레드존 주행 시 냉각 한계 초과 -> 온도 상승
                        if (temp < 130) temp <= temp + 1;
                    end 
                    else if (temp < 90) begin
                        // [워밍업] 90도까지 상승
                        if (rpm > 2000) temp <= temp + 2; // 고부하 시 빨리 오름
                        else temp <= temp + 1;            // 공회전 시 천천히 오름
                    end
                    else if (temp >= 90) begin
                        // [써모스탯 작동] 90~95도 유지
                        if (temp > 95) temp <= temp - 1; // 팬 작동으로 냉각
                    end
                end else begin
                    temp_timer <= temp_timer + 1;
                end
            end 
            else begin
                // [냉각] 시동 OFF 시 자연 냉각 (상온 25도까지)
                if (temp_timer >= 2) begin // 3초마다 1도 하강
                    temp_timer <= 0;
                    if (temp > 25) temp <= temp - 1;
                end else begin
                    temp_timer <= temp_timer + 1;
                end
            end
        end
    end
endmodule