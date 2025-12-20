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
    input is_fuel_drain,
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
    reg [4:0] decel_counter; // [추가] 감속 속도 조절용 카운터
    
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
    reg [7:0] smooth_accel; // [추가] RPM 스무딩용

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rpm_jitter <= 0;
            smooth_accel <= 0;
        end
        else if (tick_speed) begin
            rpm_jitter <= rpm_jitter + 1;
            
            // [추가] 악셀 반응 스무딩 (RPM 급락 방지)
            if (effective_accel > smooth_accel) begin
                smooth_accel <= effective_accel; // 가속은 즉시
            end else if (effective_accel < smooth_accel) begin
                // 감속은 천천히 (RPM이 서서히 떨어지도록)
                if (smooth_accel >= 8) smooth_accel <= smooth_accel - 8;
                else smooth_accel <= effective_accel;
            end
        end
    end

    // =========================================================
    // 1. 물리 엔진 (속도 및 가속도 제어)
    // =========================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin 
            speed <= 0;
            ess_trigger <= 0; 
            decel_counter <= 0;
            gear_num <= 1;
        end
        // [수정] 엔진 꺼져도 관성 주행 가능하도록 speed <= 0 로직 삭제
        else if (tick_speed) begin
            // A. 힘(Power) 계산
            // [수정] 엔진 켜져있을 때만 동력 전달
            if (engine_on && current_gear == 4'd12) power = effective_accel;       // D: 100%
            else if (engine_on && current_gear == 4'd6) power = effective_accel / 2; // R: 50%
            else power = 0; // P, N 또는 엔진 꺼짐: 동력 전달 안됨

            // B. 저항(Resistance) 계산 (속도가 빠를수록 저항 증가)
            // [수정] 180km/h 이상에서 공기 저항 급증 (최고 속도 제한 효과 + 떨림 구현)
            resistance = speed + 5 + ((speed >= 180) ? 100 : 0);
            
            // [수정] 사이드 브레이크 저항 (매우 강력한 저항 - 출발 억제)
            if (is_side_brake) resistance = resistance + 210;

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
                    decel_counter <= 0; // [추가] 가속 시 감속 카운터 리셋
                    // 후진 속도 제한 (50km/h)
                    if (current_gear == 4'd6 && speed >= 50) begin
                        // 가속 불가
                    end 
                    // [추가] Low Gear Mode 속도 제한 (RPM Redline 도달 시 가속 차단 및 엔진 브레이크)
                    // 1단: ~35km/h, 2단: ~65km/h, 3단: ~95km/h
                    else if (is_low_gear_mode && current_gear == 4'd12) begin
                        if (max_gear_limit == 1 && speed >= 35) begin 
                            if (speed > 35) speed <= speed - 1; // [수정] 제한 속도 초과 시 강제 감속
                        end
                        else if (max_gear_limit == 2 && speed >= 65) begin 
                            if (speed > 65) speed <= speed - 1; // [수정] 제한 속도 초과 시 강제 감속
                        end
                        else if (max_gear_limit == 3 && speed >= 95) begin 
                            if (speed > 95) speed <= speed - 1; // [수정] 제한 속도 초과 시 강제 감속
                        end
                        else if (speed < 250 && rpm < 7900) speed <= speed + 1;
                    end
                    else if (speed < 250 && rpm < 7900) begin // [수정] RPM Redline 제한 추가
                        speed <= speed + 1;
                    end
                end 
                // 자연 감속 (Power < Resistance)
                else if (power < resistance) begin
                    // [수정] 사이드 브레이크 감속 (강력한 마찰)
                    if (is_side_brake) begin
                        // 일반 브레이크보다는 약하지만 엔진 브레이크보다는 훨씬 강하게 감속
                        // 속도에 상관없이 일정하게 감속 (마찰력)
                        if (speed > 0) begin
                            if (decel_counter >= 2) begin 
                                speed <= speed - 1; 
                                decel_counter <= 0; 
                            end else begin
                                decel_counter <= decel_counter + 1;
                            end
                        end
                    end
                    else begin
                        // [수정] 기어별 감속 비율 적용 (계단식 감속) + 공기저항 반영
                        decel_counter <= decel_counter + 1;
                        
                        if (speed > 0) begin
                            case (gear_num)
                                6: begin
                                    // [수정] 고속 주행 시 공기저항으로 인한 빠른 감속
                                    if (speed >= 170) begin 
                                        if (decel_counter >= 2) begin speed <= speed - 1; decel_counter <= 0; end
                                    end else if (speed >= 140) begin
                                        if (decel_counter >= 5) begin speed <= speed - 1; decel_counter <= 0; end
                                    end else begin
                                        if (decel_counter >= 20) begin speed <= speed - 1; decel_counter <= 0; end
                                    end
                                end
                                5: begin
                                    if (speed >= 120) begin
                                        if (decel_counter >= 8) begin speed <= speed - 1; decel_counter <= 0; end
                                    end else begin
                                        if (decel_counter >= 15) begin speed <= speed - 1; decel_counter <= 0; end
                                    end
                                end
                                4: if (decel_counter >= 10) begin speed <= speed - 1; decel_counter <= 0; end
                                3: if (decel_counter >= 6) begin speed <= speed - 1; decel_counter <= 0; end
                                2: if (decel_counter >= 3) begin speed <= speed - 1; decel_counter <= 0; end
                                1: if (decel_counter >= 1) begin speed <= speed - 1; decel_counter <= 0; end
                                default: begin speed <= speed - 1; decel_counter <= 0; end
                            endcase
                        end
                    end
                end
                else begin
                    decel_counter <= 0;
                end

                // =========================================================
                // [추가] 기어 변속 로직 (Hysteresis 적용)
                // =========================================================
                if (current_gear == 4'd12) begin // D단
                    if (effective_accel == 0) begin
                        // Gliding Mode (사용자 요청 값 적용)
                        if (speed < 20) gear_num <= 1;
                        else if (speed < 31) gear_num <= 2;
                        else if (speed < 50) gear_num <= 3;
                        else if (speed < 71) gear_num <= 4;
                        else if (speed < 105) gear_num <= 5;
                        else gear_num <= 6;
                    end else begin
                        // Normal Mode (Hysteresis 적용)
                        // Downshift: 105, 71, 50, 31, 20
                        // Upshift: +5km/h (110, 76, 55, 36, 25)
                        case (gear_num)
                            1: if (speed >= 25) gear_num <= 2;
                            2: begin
                                if (speed < 20) gear_num <= 1;
                                else if (speed >= 36) gear_num <= 3;
                            end
                            3: begin
                                if (speed < 31) gear_num <= 2;
                                else if (speed >= 55) gear_num <= 4;
                            end
                            4: begin
                                if (speed < 50) gear_num <= 3;
                                else if (speed >= 76) gear_num <= 5;
                            end
                            5: begin
                                if (speed < 71) gear_num <= 4;
                                else if (speed >= 110) gear_num <= 6;
                            end
                            6: begin
                                if (speed < 105) gear_num <= 5;
                            end
                            default: gear_num <= 1;
                        endcase
                    end
                    
                    // Low Gear Mode 제한
                    if (is_low_gear_mode && gear_num > max_gear_limit) gear_num <= max_gear_limit;
                    
                end else begin
                    gear_num <= 1; // P, R, N에서는 1단 고정
                end
            end
        end
    end

    // =========================================================
    // 2. RPM 계산 (P/N 리미터 및 6단 자동 변속 시뮬레이션)
    // =========================================================
    always @(*) begin
        // [Latch 방지] 모든 변수의 기본값 설정
        rpm = 0;
        // gear_num = 1; // [이동] always @(posedge clk)로 이동
        // target_gear = 1; // [삭제]
        calc_rpm = 0;
        base_rpm = IDLE_RPM;

        if (!engine_on) begin
            rpm = 0;
        end
        
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
            // [수정] 기어 변속 로직은 always @(posedge clk)로 이동함
            
            // 3. RPM 계산 (기어별 선형 보간)
            case (gear_num)
                1: base_rpm = speed * 100;  // 1단: 힘 좋음
                2: base_rpm = speed * 60;   
                3: base_rpm = speed * 40;   
                4: base_rpm = speed * 30;   
                5: base_rpm = speed * 24;   // 5단: 가속형
                6: base_rpm = speed * 18;   // 6단: 항속형 (조용함)
                default: base_rpm = IDLE_RPM;
            endcase
            
            // [수정] 정차 중(속도 0)이거나 저속일 때도 최소 IDLE_RPM 유지
            if (base_rpm < IDLE_RPM) base_rpm = IDLE_RPM;
            
            // Underflow 방지 (음수가 될 경우 0 처리)
            if (base_rpm > 10000) base_rpm = IDLE_RPM; // 14bit overflow check (simple)

            // [수정] RPM에 부하(Throttle) 및 노이즈 반영
            // 가속 페달을 밟으면 RPM이 더 오름 (토크 컨버터 슬립 효과) + Jitter
            // [수정] smooth_accel을 사용하여 악셀 OFF 시 RPM이 천천히 떨어지도록 함
            rpm = base_rpm + (smooth_accel * 2) + rpm_jitter;
            
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
            // 1. 8번 버튼을 누르고 있으면 연료 강제 감소 (우선 순위 높음)
            if (is_fuel_drain) begin
                if (fuel >= 8) begin
                    fuel <= fuel - 8; 
                end
                else begin
                    fuel <= 0; 
                end
            end
            else if (engine_on) begin
                fuel_acc <= fuel_acc + 10 + (rpm / 100) + effective_accel;

                if (fuel_acc >= 5000) begin
                    // 여기도 안전장치: 0보다 클 때만 1 감소
                    if (fuel > 0) fuel <= fuel - 1;
                    fuel_acc <= 0;
                end
            end

            // --- [C. 엔진 온도 로직 (Thermostat Simulation)] ---
            // 1. 과열 구간 (RPM > 3500): 엔진이 무리하게 돔 → 온도가 빠르게 상승 (최대 130도)
            if (engine_on && rpm > 3500) begin
                if (temp < 130) begin
                    temp_acc <= temp_acc + 1;
                    if (temp_acc >= 3) begin // 빠르게 상승 (3초당 1도)
                        temp <= temp + 1;
                        temp_acc <= 0;
                    end
                end
            end
            // 2. 정상/예열 구간 (RPM <= 3500)
            else if (engine_on) begin
                // 예열: 90도 미만이면 상승
                if (temp < 90) begin
                    temp_acc <= temp_acc + 1;
                    if (temp_acc >= 10) begin // 적당히 상승 (10초당 1도)
                        temp <= temp + 1;
                        temp_acc <= 0;
                    end
                end
                // 정상: 90도 이상이면 냉각팬 작동으로 유지/하강
                else if (temp >= 90) begin
                    if (temp > 90) begin
                        temp_acc <= temp_acc + 1;
                        if (temp_acc >= 15) begin // 천천히 하강 (15초당 1도)
                            temp <= temp - 1;
                            temp_acc <= 0;
                        end
                    end
                    // 90도일 때는 유지 (temp_acc 리셋 안함 or 리셋)
                    else begin
                        temp_acc <= 0;
                    end
                end
            end
            // 3. 주차 구간 (시동 꺼짐): 상온(25도)까지 하강
            else begin
                if (temp > 25) begin
                    temp_acc <= temp_acc + 1;
                    if (temp_acc >= 20) begin // 아주 천천히 식음 (20초당 1도)
                        temp <= temp - 1;
                        temp_acc <= 0;
                    end
                end
            end
        end
    end
endmodule