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
    output reg [7:0] temp = 40,
    output reg [31:0] odometer_raw = 0,
    output reg ess_trigger = 0
);
    parameter IDLE_RPM = 800;
    
    // 물리 연산을 위한 변수
    reg [9:0] power;      // 엔진 힘
    reg [9:0] resistance; // 공기/바닥 저항
    
    // [개선 1] 불감대(Dead Zone) 적용: 노이즈 및 오프셋 보정
    // 센서 초기값이 약 45 정도로 들어오는 현상(속도 40km/h 고정)을 잡기 위해 불감대를 50으로 상향하고 오프셋 제거
    wire [7:0] effective_accel;
    assign effective_accel = (adc_accel > 50) ? (adc_accel - 50) : 8'd0;

    // 1. 물리 엔진 (가속도 기반)
    always @(posedge clk or posedge rst) begin
        if (rst) begin speed<=0; ess_trigger<=0; end
        else if (!engine_on) begin speed<=0; ess_trigger<=0; end
        else if (tick_speed) begin
            
            // A. 힘(Power) 계산: 악셀을 밟을수록 커짐
            if (current_gear == 4'd12) power = effective_accel; // D: 100% 힘
            else if (current_gear == 4'd6) power = effective_accel / 2; // R: 50% 힘
            else power = 0; // P, N: 동력 없음

            // B. 저항(Resistance) 계산: 속도가 빠를수록 저항이 커짐 (자연 감속)
            // [수정] 저항을 높여서 적은 악셀량으로 과도한 속도가 나오지 않게 함 (1:1 매핑에 가깝게)
            resistance = speed + 5; 

            // C. 속도 갱신
            if (is_brake_hard) begin // 급브레이크 (물리 무시하고 강제 감속)
                if(speed >= 8) speed <= speed - 8; else speed <= 0;
                if(speed > 50) ess_trigger <= 1;
            end 
            else if (is_brake_normal) begin // 일반브레이크
                if(speed >= 3) speed <= speed - 3; else speed <= 0;
                ess_trigger <= 0;
            end 
            else begin // 악셀 밟거나 떼는 중 (물리 적용)
                ess_trigger <= 0;
                
                // 힘이 저항보다 크면 가속 (관성 주행)
                if (power > resistance) begin
                    // [개선 2] 후진 속도 제한 (최대 50km/h)
                    if (current_gear == 4'd6 && speed >= 50) begin
                        // 속도 유지 (가속 안함)
                    end else if (speed < 250) begin
                        // [수정] 힘의 차이에 따라 가속도 차등 적용 (드라마틱한 가속감)
                        if ((power - resistance) > 50) 
                            speed <= (speed + 3 > 250) ? 250 : speed + 3;
                        else if ((power - resistance) > 20) 
                            speed <= (speed + 2 > 250) ? 250 : speed + 2;
                        else 
                            speed <= speed + 1;
                    end
                end 
                // 힘이 부족하면 감속 (자연 감속)
                else if (power < resistance) begin
                    if (speed > 0) speed <= speed - 1;   // 천천히 감속
                end
            end
        end
    end

    // 2. RPM 계산 (자동 변속 시뮬레이션)
    always @(*) begin
        if (!engine_on) rpm = 0;
        else if (current_gear == 4'd3 || current_gear == 4'd9) // P, N
            rpm = IDLE_RPM + (effective_accel * 20); // 공회전 (불감대 적용된 값 사용)
        else begin // D, R
            // 가상의 기어비 적용
            if (speed < 30)       rpm = IDLE_RPM + (speed * 90);       // 1단
            else if (speed < 60)  rpm = 1500 + ((speed - 30) * 70);    // 2단
            else if (speed < 90)  rpm = 1500 + ((speed - 60) * 50);    // 3단
            else if (speed < 130) rpm = 1600 + ((speed - 90) * 40);    // 4단
            else if (speed < 180) rpm = 1700 + ((speed - 130) * 30);   // 5단
            else                  rpm = 1800 + ((speed - 180) * 20);   // 6단
            
            if (rpm > 8000) rpm = 8000;
        end
    end

    // 3. OBD 데이터
    reg [1:0] fuel_timer; // 연료 소비 속도 조절용
    reg [3:0] odo_timer;  // Odometer Update Timer (10 seconds)

    always @(posedge clk or posedge rst) begin
        if (rst) begin fuel<=100; temp<=40; odometer_raw<=0; fuel_timer<=0; odo_timer<=0; end
        else if (engine_on && tick_1sec) begin
            // Odometer Logic: Update every 10 seconds
            odo_timer <= odo_timer + 1;
            if (odo_timer >= 10) begin
                odo_timer <= 0;
                // Accumulate Speed (Simple approximation for simulation)
                // If speed is 22km/h, adding 22 every 10s makes ODO grow visibly.
                odometer_raw <= odometer_raw + speed; 
            end
            
            // [개선 3] 연료 소비 속도 조절 (3초에 1씩 감소)
            if (speed > 0 || rpm > 1000) begin
                if (fuel_timer >= 2) begin
                    if (fuel > 0) fuel <= fuel - 1;
                    fuel_timer <= 0;
                end else begin
                    fuel_timer <= fuel_timer + 1;
                end
            end
            
            if(rpm>3000 && temp<200) temp<=temp+2; else if(temp>40) temp<=temp-1;
        end
    end
endmodule
