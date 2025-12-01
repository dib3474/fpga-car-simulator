module Keypad_Controller (
    input clk,
    input rst,

    input col_1, input col_2, input col_3,
    output reg row_1, output reg row_2, output reg row_3, output reg row_4,

    // 버튼 12개 (Debounced Output)
    output wire key_1, output wire key_2, output wire key_3,
    output wire key_4, output wire key_5, output wire key_6,
    output wire key_7, output wire key_8, output wire key_9,
    output wire key_star, output wire key_0, output wire key_sharp
);

    reg [19:0] scan_cnt;
    reg [1:0] step;
    
    // Raw inputs from keypad scan
    reg raw_key_1, raw_key_2, raw_key_3;
    reg raw_key_4, raw_key_5, raw_key_6;
    reg raw_key_7, raw_key_8, raw_key_9;
    reg raw_key_star, raw_key_0, raw_key_sharp;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            row_1 <= 1; row_2 <= 1; row_3 <= 1; row_4 <= 1;
            scan_cnt <= 0; step <= 0;
            
            raw_key_1<=0; raw_key_2<=0; raw_key_3<=0;
            raw_key_4<=0; raw_key_5<=0; raw_key_6<=0;
            raw_key_7<=0; raw_key_8<=0; raw_key_9<=0;
            raw_key_star<=0; raw_key_0<=0; raw_key_sharp<=0;
        end else begin
            if (scan_cnt < 50_000) scan_cnt <= scan_cnt + 1; // 1ms per step
            else begin
                scan_cnt <= 0;
                step <= step + 1;
            end

            case (step)
                0: begin row_1<=0; row_2<=1; row_3<=1; row_4<=1; end
                1: begin row_1<=1; row_2<=0; row_3<=1; row_4<=1; end
                2: begin row_1<=1; row_2<=1; row_3<=0; row_4<=1; end
                3: begin row_1<=1; row_2<=1; row_3<=1; row_4<=0; end
            endcase
            
            // Read Columns in the middle of the scan period (to ensure stable signal)
            if (scan_cnt == 25_000) begin
                case (step)
                    0: begin raw_key_1<=~col_1; raw_key_2<=~col_2; raw_key_3<=~col_3; end
                    1: begin raw_key_4<=~col_1; raw_key_5<=~col_2; raw_key_6<=~col_3; end
                    2: begin raw_key_7<=~col_1; raw_key_8<=~col_2; raw_key_9<=~col_3; end
                    3: begin raw_key_star<=~col_1; raw_key_0<=~col_2; raw_key_sharp<=~col_3; end
                endcase
            end
        end
    end

    // Debounce Modules for each key
    Debounce_Unit d1 (.clk(clk), .rst(rst), .in(raw_key_1), .out(key_1));
    Debounce_Unit d2 (.clk(clk), .rst(rst), .in(raw_key_2), .out(key_2));
    Debounce_Unit d3 (.clk(clk), .rst(rst), .in(raw_key_3), .out(key_3));
    Debounce_Unit d4 (.clk(clk), .rst(rst), .in(raw_key_4), .out(key_4));
    Debounce_Unit d5 (.clk(clk), .rst(rst), .in(raw_key_5), .out(key_5));
    Debounce_Unit d6 (.clk(clk), .rst(rst), .in(raw_key_6), .out(key_6));
    Debounce_Unit d7 (.clk(clk), .rst(rst), .in(raw_key_7), .out(key_7));
    Debounce_Unit d8 (.clk(clk), .rst(rst), .in(raw_key_8), .out(key_8));
    Debounce_Unit d9 (.clk(clk), .rst(rst), .in(raw_key_9), .out(key_9));
    Debounce_Unit d0 (.clk(clk), .rst(rst), .in(raw_key_0), .out(key_0));
    Debounce_Unit ds (.clk(clk), .rst(rst), .in(raw_key_star), .out(key_star));
    Debounce_Unit dh (.clk(clk), .rst(rst), .in(raw_key_sharp), .out(key_sharp));

endmodule

module Debounce_Unit (
    input clk, input rst, input in, output reg out
);
    reg [19:0] cnt;
    reg sync_in;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cnt <= 0; out <= 0; sync_in <= 0;
        end else begin
            sync_in <= in; // Synchronize input
            if (sync_in == out) begin
                cnt <= 0;
            end else begin
                cnt <= cnt + 1;
                if (cnt >= 500_000) begin // 10ms stable time
                    out <= sync_in;
                    cnt <= 0;
                end
            end
        end
    end
endmodule
