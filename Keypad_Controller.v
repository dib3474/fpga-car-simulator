module Keypad_Controller (
    input clk,
    input rst,

    input col_1, input col_2, input col_3,
    output reg row_1, output reg row_2, output reg row_3, output reg row_4,

    // 버튼 12개
    output reg key_1, output reg key_2, output reg key_3,
    output reg key_4, output reg key_5, output reg key_6,
    output reg key_7, output reg key_8, output reg key_9,
    output reg key_star, output reg key_0, output reg key_sharp
);

    reg [19:0] scan_cnt;
    reg [1:0] step;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // ★ 초기화: 모든 ROW를 High(1)로 둬서 입력 대기 상태로 만듦 (Active Low 스캔)
            row_1 <= 1; row_2 <= 1; row_3 <= 1; row_4 <= 1;
            scan_cnt <= 0; step <= 0;
            
            // 모든 키 값 0으로 초기화
            key_1<=0; key_2<=0; key_3<=0;
            key_4<=0; key_5<=0; key_6<=0;
            key_7<=0; key_8<=0; key_9<=0;
            key_star<=0; key_0<=0; key_sharp<=0;
        end else begin
            // 스캔 로직 (이전과 동일)
            if (scan_cnt < 50_000) scan_cnt <= scan_cnt + 1;
            else begin
                scan_cnt <= 0;
                step <= step + 1;
            end

            case (step)
                0: begin row_1<=0; row_2<=1; row_3<=1; row_4<=1; key_1<=~col_1; key_2<=~col_2; key_3<=~col_3; end
                1: begin row_1<=1; row_2<=0; row_3<=1; row_4<=1; key_4<=~col_1; key_5<=~col_2; key_6<=~col_3; end
                2: begin row_1<=1; row_2<=1; row_3<=0; row_4<=1; key_7<=~col_1; key_8<=~col_2; key_9<=~col_3; end
                3: begin row_1<=1; row_2<=1; row_3<=1; row_4<=0; key_star<=~col_1; key_0<=~col_2; key_sharp<=~col_3; end
            endcase
        end
    end
endmodule