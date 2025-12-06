module Display_Unit (
    input clk, 
    input rst,              // Reset
    input tick_scan, 
    input obd_mode_sw,      // 0: Normal, 1: OBD
    input [13:0] rpm, 
    input [7:0] speed, 
    input [7:0] fuel, 
    input [7:0] temp, 
    // input [7:0] accel,   // [삭제] 악셀 강도 제거
    input [3:0] gear_char, 
    input [2:0] gear_num, // [추가] 현재 기어 단수 (1~6)
    input is_low_gear_mode, // [추가]
    input [2:0] max_gear_limit, // [추가]
    
    // 8-Digit 7-Segment
    output reg [7:0] seg_data = 0, 
    output reg [7:0] seg_com = 0,

    // 1-Digit 7-Segment
    output reg [7:0] seg_1_data = 0
);

    reg [15:0] left_val = 0, right_val = 0; 
    reg [2:0] scan_idx = 0; 
    reg [3:0] hex_digit = 0;

    // --- Leading Zero Blanking BCD 변환 함수 ---
    function [15:0] to_bcd4_blank;
        input [15:0] value;
        integer temp_val;
        integer thousands, hundreds, tens, ones;
        begin
            temp_val = value;
            if (temp_val > 9999) temp_val = 9999;
            
            thousands = temp_val / 1000;
            temp_val = temp_val % 1000;
            hundreds = temp_val / 100;
            temp_val = temp_val % 100;
            tens = temp_val / 10;
            ones = temp_val % 10;

            if (thousands == 0) begin
                thousands = 4'hF; 
                if (hundreds == 0) begin
                    hundreds = 4'hF; 
                    if (tens == 0) tens = 4'hF; 
                end
            end
            to_bcd4_blank = {thousands[3:0], hundreds[3:0], tens[3:0], ones[3:0]};
        end
    endfunction

    // 7-Segment Encoder (Active High, LSB=a)
    function [7:0] encode_digit;
        input [3:0] digit;
        begin
            case (digit)
                4'h0: encode_digit = 8'b0011_1111; // 0x3F
                4'h1: encode_digit = 8'b0000_0110;
                4'h2: encode_digit = 8'b0101_1011;
                4'h3: encode_digit = 8'b0100_1111;
                4'h4: encode_digit = 8'b0110_0110;
                4'h5: encode_digit = 8'b0110_1101;
                4'h6: encode_digit = 8'b0111_1101;
                4'h7: encode_digit = 8'b0000_0111;
                4'h8: encode_digit = 8'b0111_1111;
                4'h9: encode_digit = 8'b0110_1111;
                4'hF: encode_digit = 8'b0000_0000; // Blank
                default: encode_digit = 8'b0000_0000;
            endcase
        end
    endfunction

    // --- 1. Data Selection ---
    always @(*) begin
        // [공통] 왼쪽은 항상 RPM 표시
        left_val = to_bcd4_blank({2'b0, rpm});

        if (obd_mode_sw) begin 
            // [OBD 모드] 오른쪽: 엔진 온도
            right_val = to_bcd4_blank({8'b0, temp});
        end else begin 
            // [일반 모드] 오른쪽: 속도
            right_val = to_bcd4_blank({8'b0, speed});
        end
    end

    // --- 2. Scan Timer ---
    always @(posedge clk or posedge rst) begin
        if (rst) scan_idx <= 0;
        else if (tick_scan) scan_idx <= scan_idx + 1;
    end

    // --- 3. 8-Digit Output ---
    always @(*) begin
        if (rst) begin
            seg_com = 8'hFF;
            seg_data = 8'h00; 
        end else begin
            // Active Low Common
            seg_com = 8'hFF;
            seg_com[scan_idx] = 0; 

            case (scan_idx)
                // Right Value
                0: hex_digit = right_val[3:0];
                1: hex_digit = right_val[7:4];
                2: hex_digit = right_val[11:8]; 
                3: hex_digit = right_val[15:12];
                // Left Value (RPM)
                4: hex_digit = left_val[3:0]; 
                5: hex_digit = left_val[7:4];
                6: hex_digit = left_val[11:8]; 
                7: hex_digit = left_val[15:12];
            endcase
            
            seg_data = encode_digit(hex_digit);
        end
    end

    // --- 4. 1-Digit Output (Gear) ---
    // [수정] 8-Digit와 동일한 비트 순서(LSB=a)로 코드값 변경
    // P(0x73), r(0x50), n(0x54), d(0x5E)
    // OBD 모드이고 D단일 때 기어 단수(1~6) 표시
    always @(*) begin
        if (rst) seg_1_data = 8'h00;
        else begin
            if (obd_mode_sw && gear_char == 4'd12) begin
                // OBD 모드 & D단 -> 기어 단수 표시
                case (gear_num)
                    3'd1: seg_1_data = 8'b0110_0000; // 1
                    3'd2: seg_1_data = 8'b1101_1010; // 2
                    3'd3: seg_1_data = 8'b1111_0010; // 3
                    3'd4: seg_1_data = 8'b0110_0110; // 4
                    3'd5: seg_1_data = 8'b1011_0110; // 5
                    3'd6: seg_1_data = 8'b0011_1110; // 6
                    default: seg_1_data = 8'b0000_0000;
                endcase
            end else begin
                // 일반 모드 또는 P/R/N -> 문자 표시
                case (gear_char)
                    4'd3:  seg_1_data = 8'h73; // P (a,b,e,f,g)
                    4'd6:  seg_1_data = 8'h50; // r (e,g)
                    4'd9:  seg_1_data = 8'h54; // n (c,e,g)
                    4'd12: begin // d (b,c,d,e,g)
                        if (is_low_gear_mode) begin
                            // Low Gear Mode일 때는 설정된 Limit 표시 (1, 2, 3)
                            case (max_gear_limit)
                                3'd1: seg_1_data = 8'h06; // 1
                                3'd2: seg_1_data = 8'h5B; // 2
                                3'd3: seg_1_data = 8'h4F; // 3
                                default: seg_1_data = 8'h5E; // d
                            endcase
                        end else begin
                            seg_1_data = 8'h5E; // d
                        end
                    end
                    default: seg_1_data = 8'h00;
                endcase
            end
        end
    end

endmodule