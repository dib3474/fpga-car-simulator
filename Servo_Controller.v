module Servo_Controller (
    input clk,
    input rst,
    input [7:0] speed,
    output reg servo_pwm
);
    // 20 ms period for hobby servo (50 Hz) using 50 MHz clock -> 1,000,000 cycles
    localparam integer PERIOD_CYCLES = 1_000_000;
    // SG90 Servo: 0 deg = 0.5ms (25,000), 180 deg = 2.5ms (125,000)
    localparam integer MIN_PULSE = 25_000;  // 0.5 ms (0 degree)
    localparam integer MAX_PULSE = 125_000; // 2.5 ms (180 degree)

    reg [19:0] period_cnt = 0;
    reg [19:0] pulse_width = MIN_PULSE;
    integer scaled_width;

    // Map speed (0~255) to pulse width linearly between 0.5ms and 2.5ms
    // Range = 100,000 cycles. 100,000 / 255 ≈ 392
    always @(*) begin
        scaled_width = MIN_PULSE + (speed * 392);
        if (scaled_width > MAX_PULSE) scaled_width = MAX_PULSE;
        pulse_width = scaled_width[19:0];
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            period_cnt <= 0;
            servo_pwm <= 1'b0;
        end else begin
            if (period_cnt >= PERIOD_CYCLES - 1) begin
                period_cnt <= 0;
            end else begin
                period_cnt <= period_cnt + 1'b1;
            end
            servo_pwm <= (period_cnt < pulse_width);
        end
    end
endmodule
