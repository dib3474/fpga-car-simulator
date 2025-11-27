module Vehicle_Logic (
    input clk, input rst,
    input tick_1sec, input tick_speed,
    input [3:0] current_gear, // 3:P, 6:R, 9:N, 12:D
    input [7:0] adc_accel,
    input is_brake_normal, input is_brake_hard,
    
    output reg [7:0] speed,
    output reg [13:0] rpm,
    output reg [7:0] fuel,
    output reg [7:0] temp,
    output reg [31:0] odometer_raw,
    output reg ess_trigger
);
    parameter IDLE_RPM = 800;

    // 1. 속도 및 ESS 계산
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            speed <= 0; ess_trigger <= 0;
        end else if (tick_speed) begin
            if (current_gear == 4'd12 || current_gear == 4'd6) begin // D or R
                if (is_brake_hard) begin // 급브레이크
                    if(speed >= 10) speed <= speed - 10; else speed <= 0;
                    if(speed > 50) ess_trigger <= 1;
                end else if (is_brake_normal) begin // 일반브레이크
                    if(speed >= 2) speed <= speed - 2; else speed <= 0;
                    ess_trigger <= 0;
                end else if (adc_accel > 10) begin // 가속
                    if(speed < 255) speed <= speed + 1;
                    ess_trigger <= 0;
                end else begin // 자연감속
                    if(speed > 0) speed <= speed - 1;
                    ess_trigger <= 0;
                end
            end else begin // P, N
                if(speed > 0) speed <= speed - 1;
                ess_trigger <= 0;
            end
        end
    end

    // 2. 6단 변속 및 RPM
    always @(*) begin
        case (current_gear)
            4'd3, 4'd9: rpm = IDLE_RPM + (adc_accel * 20); // P, N
            4'd6: rpm = IDLE_RPM + (speed * 60); // R
            4'd12: begin // D (6단)
                if (speed < 30)       rpm = IDLE_RPM + (speed * 100);
                else if (speed < 60)  rpm = 1500 + ((speed - 30) * 80);
                else if (speed < 90)  rpm = 1500 + ((speed - 60) * 60);
                else if (speed < 130) rpm = 1600 + ((speed - 90) * 40);
                else if (speed < 180) rpm = 1700 + ((speed - 130) * 30);
                else                  rpm = 1800 + ((speed - 180) * 20);
                if (rpm > 7000) rpm = 7000;
            end
            default: rpm = IDLE_RPM;
        endcase
    end

    // 3. OBD 데이터 (거리, 연료, 온도)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            fuel <= 100; temp <= 50; odometer_raw <= 0;
        end else if (tick_1sec) begin
            odometer_raw <= odometer_raw + speed;
            if (fuel > 0 && (speed > 0 || rpm > 1000)) fuel <= fuel - 1;
            if (rpm > 3000 && temp < 200) temp <= temp + 2;
            else if (temp > 50) temp <= temp - 1;
        end
    end
endmodule