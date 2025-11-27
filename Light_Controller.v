module Light_Controller (
    input clk,
    input rst,
    
    // 입력
    input sw_headlight,      // 수동 전조등 (SW4)
    input sw_high_beam,      // 상향등 스위치 (SW5)
    input [7:0] cds_val,     // 조도 센서 값
    input is_brake,          // 브레이크
    input turn_left,         // 좌측 깜빡이
    input turn_right,        // 우측 깜빡이
    
    // ★ 출력: Full Color LED (4개 x 3색 = 12핀)
    // [0]:LED1, [1]:LED2, [2]:LED3, [3]:LED4
    output wire [3:0] fc_red,
    output wire [3:0] fc_green,
    output wire [3:0] fc_blue,
    
    // 출력: 일반 LED
    output [7:0] led_port
);

    // 1. 오토라이트 판단
    wire is_dark = (cds_val < 100); 
    wire head_on = sw_headlight || is_dark; // 전조등 ON 조건
    
    // 2. 전조등 로직 (White Color: R+G+B 모두 ON)
    // 하향등 (아래 2개: LED3, LED4 -> 인덱스 2, 3)
    // 상향등 (위 2개: LED1, LED2 -> 인덱스 0, 1)
    
    wire low_beam_on = head_on; 
    wire high_beam_on = head_on && sw_high_beam; // 전조등 켜진 상태에서 상향등 스위치

    // 각각의 LED 제어 (Active Low인지 High인지 확인 필요, 보통 High=ON)
    // LED 1 (상향등)
    assign fc_red[0]   = high_beam_on;
    assign fc_green[0] = high_beam_on;
    assign fc_blue[0]  = high_beam_on;
    
    // LED 2 (상향등)
    assign fc_red[1]   = high_beam_on;
    assign fc_green[1] = high_beam_on;
    assign fc_blue[1]  = high_beam_on;
    
    // LED 3 (하향등)
    assign fc_red[2]   = low_beam_on;
    assign fc_green[2] = low_beam_on;
    assign fc_blue[2]  = low_beam_on;
    
    // LED 4 (하향등)
    assign fc_red[3]   = low_beam_on;
    assign fc_green[3] = low_beam_on;
    assign fc_blue[3]  = low_beam_on;

    // 3. 후미등(미등/브레이크등) PWM (기존 로직 유지)
    reg [4:0] pwm_cnt;
    always @(posedge clk) pwm_cnt <= pwm_cnt + 1;
    wire dim_light = pwm_cnt[4]; 
    wire tail_light_on = is_brake ? 1'b1 : (head_on ? dim_light : 1'b0);

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