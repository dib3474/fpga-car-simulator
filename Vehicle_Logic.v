module Vehicle_Logic (
    input clk, input rst,
    input engine_on,
    input tick_1sec, input tick_speed, // tick_speed: 약 0.05초 가정
    input [3:0] current_gear, // 3:P, 6:R, 9:N, 12:D
    input [7:0] adc_accel,
    input is_brake_normal, input is_brake_hard,
    
    output reg [7:0] speed = 0,
    output reg [13:0] rpm = 0,
    output reg [7:0] fuel = 100,
    output reg [7:0] temp = 25,
    output reg [31:0] odometer_raw = 0, // 단위: 미터(m)
    output reg ess_trigger = 0
);
    parameter IDLE_RPM = 800;
    
    // 물리 연산 변수
    reg [9:0] power;      
    reg [9:0] resistance; 
    
    // 불감대 적용
    wire [7:0] effective_accel;
    assign effective_accel = (adc_accel > 5) ? (adc_accel - 5) : 8'd0;

    reg [13:0] calc_rpm; 

    // =========================================================
    // 1. 물리 엔진 (속도/가속도)
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
            // A. 힘(Power)
            if (current_gear == 4'd12) power = effective_accel;       
            else if (current_gear == 4'd6) power = effective_accel / 2; 
            else power = 0; 

            // B. 저항(Resistance)
            resistance = speed + 5;

            // C. 속도 갱신
            if (is_brake_hard) begin 
                if (speed > 150) begin if(speed>=2) speed<=speed-2; else speed<=0; end
                else if (speed > 80) begin if(speed>=4) speed<=speed-4; else speed<=0; end
                else begin if(speed>=8) speed<=speed-8; else speed<=0; end
                
                if(speed > 50) ess_trigger <= 1; else ess_trigger <= 0;
            end 
            else if (is_brake_normal) begin 
                if (speed > 150) begin if(speed>=1) speed<=speed-1; else speed<=0; end
                else if (speed > 80) begin if(speed>=2) speed<=speed-2; else speed<=0; end
                else begin if(speed>=3) speed<=speed-3; else speed<=0; end
                ess_trigger <= 0;
            end 
            else begin 
                ess_trigger <= 0;
                if (power > resistance) begin
                    if (current_gear == 4'd6 && speed >= 50) begin end 
                    else if (speed < 250) speed <= speed + 1;
                end 
                else if (power < resistance) begin
                    if (speed > 0) speed <= speed - 1;
                end
            end
        end
    end

    // =========================================================
    // 2. RPM 계산
    // =========================================================
    always @(*) begin
        if (!engine_on) rpm = 0;
        else if (current_gear == 4'd3 || current_gear == 4'd9) begin 
            calc_rpm = IDLE_RPM + (effective_accel * 20);
            if (calc_rpm > 4000) rpm = 4000; else rpm = calc_rpm;
        end
        else begin 
            if (speed < 40)       rpm = IDLE_RPM + (speed * 100);
            else if (speed < 80)  rpm = 1500 + ((speed - 40) * 80);
            else if (speed < 120) rpm = 1500 + ((speed - 80) * 60);
            else if (speed < 160) rpm = 1600 + ((speed - 120) * 50);
            else if (speed < 200) rpm = 1700 + ((speed - 160) * 40);
            else                  rpm = 1800 + ((speed - 200) * 30);
            if (rpm > 8000) rpm = 8000;
        end
    end

    // =========================================================
    // 3. OBD 데이터 (거리, 온도, 연료 - 현실적 로직 적용)
    // =========================================================
    reg [2:0] temp_timer;     
    reg [15:0] dist_cm_acc;   
    
    // [연료 소비 로직 변수]
    reg [15:0] fuel_accum; 
    parameter FUEL_THRESHOLD = 5000; // 이 값이 찰 때마다 연료 1% 감소

    always @(posedge clk or posedge rst) begin
        if (rst) begin 
            fuel <= 100;
            temp <= 25;       
            odometer_raw <= 0; 
            temp_timer <= 0;
            dist_cm_acc <= 0;
            fuel_accum <= 0;
        end
        else if (tick_1sec) begin
            // --- [거리 계산 로직 수정] ---
            // 속도(km/h)를 바로 더하는 게 아니라, "1초 동안 이동한 거리(cm)"를 더합니다.
            // 1 km/h = 1000m / 3600s = 0.2777 m/s = 약 27.77 cm/s
            // 즉, (현재 속도 * 28) cm 만큼 이동한 것입니다. 절대 그냥 더하는 게 아닙니다!
            if (engine_on && speed > 0) begin
                dist_cm_acc <= dist_cm_acc + (speed * 28); // cm 단위 적분
                
                if (dist_cm_acc >= 100) begin
                    odometer_raw <= odometer_raw + (dist_cm_acc / 100); // 100cm -> 1m 증가
                    dist_cm_acc <= dist_cm_acc % 100;
                end
            end
            
            // 온도 제어
            if (engine_on) begin
                if (temp_timer >= 1) begin 
                    temp_timer <= 0;
                    if (rpm > 5000 && temp < 130) temp <= temp + 1;
                    else if (temp < 90) begin
                        if (rpm > 2000) temp <= temp + 2; else temp <= temp + 1;
                    end
                    else if (temp >= 90) begin
                        if (temp > 95) temp <= temp - 1; 
                    end
                end else temp_timer <= temp_timer + 1;
            end else begin
                if (temp_timer >= 2) begin 
                    temp_timer <= 0;
                    if (temp > 25) temp <= temp - 1;
                end else temp_timer <= temp_timer + 1;
            end
        end
        
        // --- [연료 소비 로직 수정] tick_speed(약 0.05초)마다 계산 ---
        else if (tick_speed && engine_on) begin
            reg [15:0] drain_amount;
            drain_amount = 0;

            // 1. 공회전 기본 소모
            drain_amount = 2; 

            // 2. RPM 비례 소모
            drain_amount = drain_amount + (rpm / 1000);

            // 3. 악셀 부하 비례 소모
            if (effective_accel > 10) begin
                drain_amount = drain_amount + (effective_accel / 5);
            end

            // 4. 퓨얼컷 (주행 중 악셀 OFF시 연료 차단)
            if (rpm > 1500 && effective_accel == 0) begin
                drain_amount = 0; 
            end

            fuel_accum <= fuel_accum + drain_amount;

            if (fuel_accum >= FUEL_THRESHOLD) begin
                if (fuel > 0) fuel <= fuel - 1;
                fuel_accum <= 0; 
            end
        end
    end
endmodule