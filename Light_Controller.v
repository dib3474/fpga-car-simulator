module Light_Controller (
    input clk,
    input rst,
    
    // 입력
    input sw_headlight,      // 전조등 스위치 (SW4)
    input sw_high_beam,      // 상향등 스위치 (SW5)
    input [7:0] cds_val,     // 조도 센서 값
    input is_brake,          // 브레이크
    input is_reverse,        // 후진 기어 (R) 상태
    input turn_left,         // 좌측 깜빡이
    input turn_right,        // 우측 깜빡이
    
    // 풀 컬러 LED (4개 x 3색 = 12핀)
    // [0]:LED1, [1]:LED2, [2]:LED3, [3]:LED4
    output wire [3:0] fc_red,
    output wire [3:0] fc_green,
    output wire [3:0] fc_blue,
    
    // 출력: 일반 LED
    output [7:0] led_port
);

    // 1. 오토라이트 판단 (히스테리시스 적용)
    // [수정] 센서 감도 조절: 조건을 완화하여 조금만 어두워도 켜지도록 변경
    // 200 미만이면 켜짐 (기존 150보다 완화), 220 초과면 꺼짐 (채터링 방지)
    reg is_dark;
    always @(posedge clk or posedge rst) begin
        if (rst) is_dark <= 0;
        else begin
            if (cds_val < 200) is_dark <= 1;      // 어두움 (ON)
            else if (cds_val > 220) is_dark <= 0; // 밝음 (OFF)
        end
    end

    wire head_on = sw_headlight || is_dark; // 전조등 ON 조건
    
    // 2. 전조등 제어 (White Color: R+G+B 모두 ON)
    // 하향등 (아래 2개: LED3, LED4 -> 인덱스 2, 3)
    // 상향등 (위 2개: LED1, LED2 -> 인덱스 0, 1)
    
    wire low_beam_on = head_on; 
    wire high_beam_on = head_on && sw_high_beam; // 전조등 켜진 상태에서 상향등 스위치

    // 풀컬러 LED 매핑 (Active Low인지 High인지 확인 필요, 여기선 High=ON)
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

    // 3. 테일램프/브레이크등/후진등 PWM 제어
    // PWM 카운터: 0~9 (10단계 밝기 조절)
    reg [3:0] pwm_cnt;
    always @(posedge clk) begin
        if (pwm_cnt >= 9) pwm_cnt <= 0;
        else pwm_cnt <= pwm_cnt + 1;
    end

    // 밝기 설정
    // 100% (브레이크): 항상 1
    // 70% (후진등): pwm_cnt < 7
    // 30% (미등): pwm_cnt < 3
    
    wire pwm_100 = 1'b1;
    wire pwm_70  = (pwm_cnt < 7);
    wire pwm_30  = (pwm_cnt < 3);

    // 각 LED 별 밝기 로직
    // 바깥쪽 (LED 5, 2): 브레이크(100%) > 미등(30%)
    // 안쪽 (LED 4, 3): 후진(70%) > 브레이크(100%) > 미등(30%)
    
    wire tail_outer; // LED 5, 2
    wire tail_inner; // LED 4, 3

    assign tail_outer = is_brake ? pwm_100 : (head_on ? pwm_30 : 1'b0);
    
    // 안쪽 등: 후진(R)이면 70%, 아니면 (브레이크 100% or 미등 30%)
    assign tail_inner = is_reverse ? pwm_70 : (is_brake ? pwm_100 : (head_on ? pwm_30 : 1'b0));

    // 4. 일반 LED 출력
    assign led_port[7] = turn_left;
    assign led_port[6] = turn_left;
    assign led_port[5] = tail_outer;
    assign led_port[4] = tail_inner; // 후진등 겸용
    assign led_port[3] = tail_inner; // 후진등 겸용
    assign led_port[2] = tail_outer;
    assign led_port[1] = turn_right;
    assign led_port[0] = turn_right;

endmodule