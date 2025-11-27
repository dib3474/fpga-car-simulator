module Vehicle_Logic (
    input clk, input rst, 
    input tick_1sec, input tick_speed, // tick_speed는 약 0.05초(20Hz) 권장
    
    input [3:0] current_gear, 
    input [7:0] adc_accel,    // 악셀 밟은 힘 (0~255)
    input is_brake_normal, input is_brake_hard, input is_start_btn,
    
    output reg engine_on,
    output reg [7:0] speed,
    output reg [13:0] rpm,
    output reg [7:0] fuel,
    output reg [7:0] temp,
    output reg [31:0] odometer_raw,
    output reg ess_trigger
);
    parameter IDLE_RPM = 800;
    reg prev_start_btn;
    
    // 물리 연산을 위한 변수
    reg [9:0] power;      // 엔진 힘
    reg [9:0] resistance; // 공기/바닥 저항

    // 1. 시동 로직 (브레이크 + 시동버튼)
    always @(posedge clk or posedge rst) begin
        if (rst) begin engine_on<=0; prev_start_btn<=0; end
        else begin
            prev_start_btn <= is_start_btn;
            // 버튼 누른 순간(Rising) & 브레이크 밟고있음 -> 토글
            if (is_start_btn && !prev_start_btn && is_brake_normal) 
                engine_on <= ~engine_on;
        end
    end

    // 2. ★ 물리 엔진 (가속도 기반)
    always @(posedge clk or posedge rst) begin
        if (rst) begin speed<=0; ess_trigger<=0; end
        else if (!engine_on) begin speed<=0; ess_trigger<=0; end
        else if (tick_speed) begin
            
            // A. 힘(Power) 계산: 악셀을 밟을수록 커짐
            if (current_gear == 4'd12) power = adc_accel; // D: 100% 힘
            else if (current_gear == 4'd6) power = adc_accel / 2; // R: 50% 힘
            else power = 0; // P, N: 동력 없음

            // B. 저항(Resistance) 계산: 속도가 빠를수록 저항이 커짐 (자연 감속)
            resistance = speed / 4 + 2; // 기본 마찰 2 + 속도 비례 저항

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
                    if (speed < 250) speed <= speed + 1; // 천천히 가속
                end 
                // 힘이 부족하면 감속 (자연 감속)
                else if (power < resistance) begin
                    if (speed > 0) speed <= speed - 1;   // 천천히 감속
                end
            end
        end
    end

    // 3. RPM 계산 (자동 변속 시뮬레이션)
    always @(*) begin
        if (!engine_on) rpm = 0;
        else if (current_gear == 4'd3 || current_gear == 4'd9) // P, N
            rpm = IDLE_RPM + (adc_accel * 20); // 공회전
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

    // 4. OBD 데이터
    always @(posedge clk or posedge rst) begin
        if (rst) begin fuel<=100; temp<=40; odometer_raw<=0; end
        else if (engine_on && tick_1sec) begin
            odometer_raw <= odometer_raw + speed;
            if(fuel>0 && (speed>0 || rpm>1000)) fuel<=fuel-1;
            if(rpm>3000 && temp<200) temp<=temp+2; else if(temp>40) temp<=temp-1;
        end
    end
endmodule