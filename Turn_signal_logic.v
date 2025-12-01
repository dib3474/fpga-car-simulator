module Turn_Signal_Logic (
    input clk, input rst,
    input sw_left, input sw_right, input sw_hazard, input ess_active,
    output wire led_left, output wire led_right
);
    reg [25:0] blink_cnt;
    wire blink_pulse;

    always @(posedge clk or posedge rst) begin
        if (rst) blink_cnt <= 0;
        else if (blink_cnt >= 50_000_000) blink_cnt <= 0; // 1Hz (1s)
        else blink_cnt <= blink_cnt + 1;
    end
    assign blink_pulse = (blink_cnt < 25_000_000); // 50% Duty

    assign led_left  = (sw_left || sw_hazard || ess_active) ? blink_pulse : 1'b0;
    assign led_right = (sw_right || sw_hazard || ess_active) ? blink_pulse : 1'b0;
endmodule