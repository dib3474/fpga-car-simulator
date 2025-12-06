module Vehicle_Logic (
    input clk, input rst,
    input engine_on,
    input tick_1sec, input tick_speed,
    input [3:0] current_gear, // 3:P, 6:R, 9:N, 12:D
    input is_low_gear_mode, // [추가] Low Gear Mode
    input [2:0] max_gear_limit, // [추가] Max Gear Limit
    input is_side_brake, // [추가] 사이드 브레이크
    input [7:0] adc_accel,
    input is_brake_normal, input is_brake_hard,
    
    output reg [7:0] speed = 0,
    output reg [13:0] rpm = 0,
    output reg [7:0] fuel = 100,
    output reg [7:0] temp = 25,      // 초기 온도: 상온 25도
    output reg [31:0] odometer_raw = 0, // 총 주행 거리 (단위: 미터)
    output reg ess_trigger = 0,
    output reg [2:0] gear_num = 1 // [추가] 현재 기어 단수 (1~6)
);
    parameter IDLE_RPM = 800;
    
    // 물리 연산을 위한 변수
    reg [9:0] power;      // 엔진 힘
    reg [9:0] resistance; // 공기/바닥 저항
    
    // [개선] 불감대(Dead Zone) 적용: 노이즈 제거
    // 속도 제어용 (노이즈로 인한 미세 전진 방지)
    wire [7:0] effective_accel;
    assign effective_accel = (adc_accel > 5) ? (adc_accel - 5) : 8'd0;
    
    // RPM 표시용 (데드존 없이 원본 값 사용 -> 미세한 떨림 표현)
    wire [7:0] rpm_accel;
    assign rpm_accel = adc_accel;

    // 계산용 임시 변수
    reg [13:0] calc_rpm; 
    reg [13:0] base_rpm; 
    reg [2:0] target_gear; // [추가] 변속 로직용 임시 변수 

    // [추가] RPM Jitter (0~3) - 엔진 진동 시뮬레이션
    reg [1:0] rpm_jitter;
    always @(posedge clk or posedge rst) begin
        if (rst) rpm_jitter <= 0;
        else if (tick_speed) rpm_jitter <= rpm_jitter + 1;
    end

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
            // [수정] 180km/h 이상에서 공기 저항 급증 (최고 속도 제한 효과 + 떨림 구현)
            resistance = speed + 5 + ((speed >= 180) ? 100 : 0);
            
            // [추가] 사이드 브레이크 저항 (매우 강력한 저항)
            if (is_side_brake) resistance = resistance + 50;

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
                    end 
                    // [추가] Low Gear Mode 속도 제한 (RPM Redline 도달 시 가속 차단)
                    // 1단: ~30km/h, 2단: ~60km/h, 3단: ~90km/h
                    else if (is_low_gear_mode && current_gear == 4'd12) begin
                        if (max_gear_limit == 1 && speed >= 35) begin /* Limit */ end
                        else if (max_gear_limit == 2 && speed >= 65) begin /* Limit */ end
                        else if (max_gear_limit == 3 && speed >= 95) begin /* Limit */ end
                        else if (speed < 250 && rpm < 7900) speed <= speed + 1;
                    end
                    else if (speed < 250 && rpm < 7900) begin // [수정] RPM Redline 제한 추가
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
            // 가상 RPM 계산 (데드존 없는 rpm_accel 사용) + Jitter
            calc_rpm = IDLE_RPM + (rpm_accel * 20) + rpm_jitter;
            
            // [Rev Limiter] P단 풀악셀 시 엔진 보호를 위해 4000 RPM 제한
            // [수정] 제한 걸려도 떨림은 유지되도록 수정
            if (calc_rpm > 4000) rpm = 4000 + rpm_jitter;
            else rpm = calc_rpm;
        end
        
        // --- D, R 상태 (주행 중) ---
        else begin 
            // [수정] Low Gear Mode 적용을 위한 로직 변경
            
            // 1. 속도에 따른 목표 기어 계산 (Auto Logic)
            if (speed < 30) target_gear = 1;
            else if (speed < 60) target_gear = 2;
            else if (speed < 90) target_gear = 3;
            else if (speed < 120) target_gear = 4;
            else if (speed < 150) target_gear = 5;
            else target_gear = 6;
            
            // 2. 기어 제한 적용 (DIP_SW[5] ON & D단일 때)
            if (is_low_gear_mode && current_gear == 4'd12) begin
                if (target_gear > max_gear_limit) gear_num = max_gear_limit;
                else gear_num = target_gear;
            end else begin
                gear_num = target_gear;
            end
            
            // 3. RPM 계산 (기어별 선형 보간)
            case (gear_num)
                1: base_rpm = IDLE_RPM + (speed * 60); 
                2: base_rpm = 450 + (speed * 35); // 1500 + (speed-30)*35 = 1500 + 35s - 1050 = 450 + 35s
                3: base_rpm = (speed * 35) - 600; // 1500 + (speed-60)*35 = 1500 + 35s - 2100 = 35s - 600
                4: base_rpm = (speed * 30) - 1100; // 1600 + (speed-90)*30 = 1600 + 30s - 2700 = 30s - 1100
                5: base_rpm = (speed * 27) - 1540; // 1700 + (speed-120)*27 = 1700 + 27s - 3240 = 27s - 1540
                6: base_rpm = (speed * 27) - 2250; // 1800 + (speed-150)*27 = 1800 + 27s - 4050 = 27s - 2250
                default: base_rpm = IDLE_RPM;
            endcase
            
            // Underflow 방지 (음수가 될 경우 0 처리)
            if (base_rpm > 10000) base_rpm = IDLE_RPM; // 14bit overflow check (simple)

            // [수정] RPM에 부하(Throttle) 및 노이즈 반영
            // 가속 페달을 밟으면 RPM이 더 오름 (토크 컨버터 슬립 효과) + Jitter
            rpm = base_rpm + (effective_accel * 2) + rpm_jitter;
            
            // 주행 중 레드존 제한 (8000 RPM)
            if (rpm > 8000) rpm = 8000;
        end
    end

    // =========================================================
    // 3. OBD 데이터 (연료, 온도, 거리) - [현실적 물리 적용]
    // =========================================================
    reg [15:0] fuel_acc;      // 연료 소모 누적기
    reg [15:0] temp_acc;      // 온도 변화 누적기
    reg [31:0] dist_m_acc;    // 거리 정밀 계산용 (미터 단위 누적)

    always @(posedge clk or posedge rst) begin
        if (rst) begin 
            fuel <= 100;
            temp <= 25;       // 초기값: 상온 25도
            odometer_raw <= 0; 
            fuel_acc <= 0;
            temp_acc <= 0;
            dist_m_acc <= 0;
        end
        else if (tick_1sec) begin
            
            // --- [A. 거리 계산 로직 (Physics Based)] ---
            // 공식: 1 km/h = 초당 약 27.77cm 이동 -> 1초에 0.2777m
            // 기존 로직은 1m마다 odometer를 1씩 올렸는데, odometer 단위가 km라면 1000m마다 올려야 함.
            // [수정] odometer_raw 단위를 km로 가정하고, 1000m(1km) 누적 시 +1
            // 1 km/h = 1000m / 3600s = 0.2777... m/s
            // 계산 편의를 위해: speed * 278 (단위: mm) -> 1,000,000 mm = 1 km
            if (engine_on && speed > 0) begin
                dist_m_acc <= dist_m_acc + (speed * 278); // mm 단위 누적
                
                // 1,000,000 mm = 1 km
                if (dist_m_acc >= 1_000_000) begin
                    odometer_raw <= odometer_raw + 1;
                    dist_m_acc <= dist_m_acc - 1_000_000;
                end
            end

            // --- [B. 연료 소비 로직 (RPM + Load)] ---
            // 공회전: 기본 소모
            // 고RPM/가속: 추가 소모
            if (engine_on) begin
                // 소모량 계산: 기본(10) + RPM비례(rpm/100) + 가속비례(accel)
                // 예: 800rpm -> 10+8=18, 3000rpm -> 10+30=40
                fuel_acc <= fuel_acc + 10 + (rpm / 100) + effective_accel;
                
                // 누적치가 일정 수준(예: 5000) 넘으면 연료 1% 감소
                if (fuel_acc >= 5000) begin
                    if (fuel > 0) fuel <= fuel - 1;
                    fuel_acc <= 0;
                end
            end

            // --- [C. 엔진 온도 로직 (Thermostat Simulation)] ---
            // 엔진은 90도(적정 온도)를 유지하려 하고, RPM이 높으면 과열됨
            if (engine_on) begin
                // 목표 온도 계산: 기본 90도 + 부하(RPM/100)
                // 예: 2000rpm -> 110도 타겟(팬이 돌아서 90 유지하려 함)
                // 실제로는 천천히 변함
                
                // 가열 요인: RPM이 높거나 가속 중일 때
                if (rpm > 2500 || effective_accel > 50) begin
                    if (temp < 130) temp_acc <= temp_acc + 1;
                end 
                // 냉각 요인: 저부하 주행 시 90도로 복귀
                else if (temp > 90) begin
                    // 가열 멈춤 (temp_acc 리셋)
                    // 90도 초과 시 천천히 식음 (쿨링 팬/라디에이터 효과)
                    if (temp_acc >= 20) begin
                        temp <= temp - 1;
                        temp_acc <= 0;
                    end else begin
                        temp_acc <= temp_acc + 1;
                    end
                end
                else if (temp < 90) begin
                    // 워밍업
                    temp_acc <= temp_acc + 1;
                end
                
                // 온도 업데이트 (가열 로직)
                // 위에서 temp_acc가 증가했을 때, 10에 도달하면 온도 상승
                // 단, 냉각 모드(temp > 90)일 때는 위에서 처리했으므로 여기서는 무시해야 함
                if (temp <= 90 && temp_acc >= 10) begin 
                    temp <= temp + 1;
                    temp_acc <= 0;
                end
                
                // 과열 방지 (팬 동작 시뮬레이션): 95도 넘으면 강제 냉각
                if (temp > 95) begin
                    if (rpm < 3000) temp <= temp - 1; // 고부하 아니면 식음
                end
            end 
            else begin
                // [냉각] 시동 OFF 시 자연 냉각 (상온 25도까지)
                if (temp > 25) begin
                    temp <= temp - 1;
                end
            end
        end
    end
endmodule