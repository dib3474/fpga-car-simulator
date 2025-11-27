module Light_Controller (
    input clk, input rst,
    input engine_on,         
    input [3:0] current_gear,
    input sw_headlight, 
    input sw_high_beam,
    input [7:0] cds_val, 
    input is_brake, 
    input turn_left, input turn_right,
    
    output wire [3:0] fc_red, output wire [3:0] fc_green, output wire [3:0] fc_blue,
    output [7:0] led_port
);

    // 1. 라이트 조건
    wire is_dark = (cds_val < 100); 
    wire head_on = (engine_on) && (sw_headlight || is_dark); 
    wire reverse_on = (engine_on) && (current_gear == 4'd6); // 후진등 (기어 R)

    // 2. Full Color LED 제어 (직접 제어 방식)
    // 상향등: 1,2번 / 하향등: 3,4번
    
    wire light_top_on = head_on && sw_high_beam; 
    wire light_bot_on = head_on || reverse_on;   // 하향등 or 후진등

    // RGB 출력 (흰색)
    assign fc_red   = {light_bot_on, light_bot_on, light_top_on, light_top_on}; 
    assign fc_green = {light_bot_on, light_bot_on, light_top_on, light_top_on};
    assign fc_blue  = {light_bot_on, light_bot_on, light_top_on, light_top_on};

    // 3. 후미등 PWM
    reg [4:0] pwm_cnt;
    always @(posedge clk) pwm_cnt <= pwm_cnt + 1;
    wire dim_light = pwm_cnt[4]; 
    
    wire tail_light_on = !engine_on ? 0 : (is_brake ? 1'b1 : (head_on ? dim_light : 1'b0));

    // 4. 일반 LED 출력
    assign led_port[7] = turn_left;  
    assign led_port[6] = turn_left;
    assign led_port[5] = tail_light_on; 
    assign led_port[4] = tail_light_on;
    assign led_port[3] = tail_light_on;
    assign led_port[2] = tail_light_on;
    assign led_port[1] = turn_right; 
    assign led_port[0] = turn_right;

endmodule