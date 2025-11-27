module Display_Unit (
    input clk, input rst, input tick_scan, input obd_mode_sw, input engine_on,
    input [13:0] rpm, input [7:0] speed, input [7:0] fuel, input [7:0] temp, input [3:0] gear_char,
    output reg [7:0] seg_data, output reg [7:0] seg_com, output reg [7:0] seg_1_data 
);
    reg [15:0] left_val_bin, right_val_bin; 
    reg [3:0] digit_val;
    reg [2:0] scan_idx; 
    
    // BCD 변환용 (0~9999)
    function [3:0] get_digit;
        input [15:0] val; input [1:0] pos;
        begin
            case(pos)
                0: get_digit = val % 10;
                1: get_digit = (val / 10) % 10;
                2: get_digit = (val / 100) % 10;
                3: get_digit = (val / 1000) % 10;
            endcase
        end
    endfunction

    always @(*) begin
        if (obd_mode_sw) begin left_val_bin={8'b0, fuel}; right_val_bin={8'b0, temp}; end 
        else begin left_val_bin={2'b0, rpm}; right_val_bin={8'b0, speed}; end
    end

    always @(posedge clk) if (tick_scan) scan_idx <= scan_idx + 1;

    // 8-Digit 출력
    always @(*) begin
        if (!engine_on && !rst) begin
            seg_com = 8'hFF; seg_data = 8'h00; // 꺼짐
        end else begin
            seg_com = 8'hFF; seg_com[scan_idx] = 0; // Active Low COM
            
            // 데이터 선택 (스캔 인덱스에 따라)
            if (scan_idx < 4) digit_val = get_digit(right_val_bin, scan_idx);
            else digit_val = get_digit(left_val_bin, scan_idx - 4);
            
            // 폰트 (Active High: 1이 켜짐)
            case (digit_val)
                0: seg_data = 8'b0011_1111; 1: seg_data = 8'b0000_0110;
                2: seg_data = 8'b0101_1011; 3: seg_data = 8'b0100_1111;
                4: seg_data = 8'b0110_0110; 5: seg_data = 8'b0110_1101;
                6: seg_data = 8'b0111_1101; 7: seg_data = 8'b0000_0111;
                8: seg_data = 8'b0111_1111; 9: seg_data = 8'b0110_1111;
                default: seg_data = 8'b0000_0000;
            endcase
        end
    end

    // 1-Digit 기어 (Active High)
    always @(*) begin
        if (!engine_on) seg_1_data = 8'h00;
        else begin
            case (gear_char)
                4'd3:  seg_1_data = 8'b0111_0011; // P
                4'd6:  seg_1_data = 8'b0101_0000; // r
                4'd9:  seg_1_data = 8'b0101_0100; // n
                4'd12: seg_1_data = 8'b0101_1110; // d
                default: seg_1_data = 8'b0000_0000;
            endcase
        end
    end
endmodule