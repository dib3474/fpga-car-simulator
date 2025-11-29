module Display_Unit (
    input clk, 
    input rst,              // Reset
    input tick_scan, 
    input obd_mode_sw,
    input [13:0] rpm, 
    input [7:0] speed, 
    input [7:0] fuel, 
    input [7:0] temp, 
    input [3:0] gear_char, 
    
    // 8-Digit 7-Segment
    output reg [7:0] seg_data = 0, 
    output reg [7:0] seg_com = 0,

    // 1-Digit 7-Segment
    output reg [7:0] seg_1_data = 0
);

    reg [15:0] left_val = 0, right_val = 0; 
    reg [2:0] scan_idx = 0; 
    reg [3:0] hex_digit = 0;

    // Convert 0~9999 value into four packed BCD digits.
    function [15:0] to_bcd4;
        input [15:0] value;
        integer temp;
        integer thousands, hundreds, tens, ones;
        begin
            temp = value;
            if (temp > 9999) temp = 9999;
            thousands = temp / 1000;
            temp = temp % 1000;
            hundreds = temp / 100;
            temp = temp % 100;
            tens = temp / 10;
            ones = temp % 10;
            to_bcd4 = {thousands[3:0], hundreds[3:0], tens[3:0], ones[3:0]};
        end
    endfunction

    // Active-High encoder (1 is ON)
    function [7:0] encode_digit;
        input [3:0] digit;
        begin
            case (digit)
                4'h0: encode_digit = 8'b0011_1111;
                4'h1: encode_digit = 8'b0000_0110;
                4'h2: encode_digit = 8'b0101_1011;
                4'h3: encode_digit = 8'b0100_1111;
                4'h4: encode_digit = 8'b0110_0110;
                4'h5: encode_digit = 8'b0110_1101;
                4'h6: encode_digit = 8'b0111_1101;
                4'h7: encode_digit = 8'b0000_0111;
                4'h8: encode_digit = 8'b0111_1111;
                4'h9: encode_digit = 8'b0110_1111;
                4'hA: encode_digit = 8'b0111_0111;
                4'hB: encode_digit = 8'b0111_1100;
                4'hC: encode_digit = 8'b0011_1001;
                4'hD: encode_digit = 8'b0101_1110;
                4'hE: encode_digit = 8'b0111_1001;
                4'hF: encode_digit = 8'b0111_0001;
                default: encode_digit = 8'b0000_0000;
            endcase
        end
    endfunction

    // --- 1. Data Selection ---
    always @(*) begin
        if (obd_mode_sw) begin 
            left_val = to_bcd4({8'b0, fuel});
            right_val = to_bcd4({8'b0, temp});
        end else begin 
            left_val = to_bcd4({2'b0, rpm});
            right_val = to_bcd4({8'b0, speed});
        end
    end

    // --- 2. Scan Timer ---
    always @(posedge clk or posedge rst) begin
        if (rst) scan_idx <= 0;
        else if (tick_scan) scan_idx <= scan_idx + 1;
    end

    // --- 3. 8-Digit Output (Active High Data, Active Low Common) ---
    always @(*) begin
        if (rst) begin
            seg_com = 8'hFF; 
            seg_data = 8'h00; 
        end else begin
            // Active Low Common
            seg_com = 8'hFF; 
            seg_com[scan_idx] = 0; 

            // Digit Selection
            case (scan_idx)
                0: hex_digit = right_val[3:0]; 1: hex_digit = right_val[7:4];
                2: hex_digit = right_val[11:8]; 3: hex_digit = right_val[15:12];
                4: hex_digit = left_val[3:0]; 5: hex_digit = left_val[7:4];
                6: hex_digit = left_val[11:8]; 7: hex_digit = left_val[15:12];
            endcase
            
            seg_data = encode_digit(hex_digit);
        end
    end

    // --- 4. 1-Digit Output (Active High Data with Pin Remapping) ---
    // Remapping based on observation: P->3, R->(c,d)
    // Logical Segments: a, b, c, d, e, f, g
    // --- 4. 1-Digit Output (Hardcoded Patterns) ---
    // P: 0x5E, r: 0x0C, n: 0x0D, d: 0x2F (Based on pin remapping)
    always @(*) begin
        if (rst) seg_1_data = 8'h00; 
        else begin
            case (gear_char)
                4'd3:  seg_1_data = 8'h5E; // P
                4'd6:  seg_1_data = 8'h0C; // r
                4'd9:  seg_1_data = 8'h0D; // n
                4'd12: seg_1_data = 8'h2F; // d
                default: seg_1_data = 8'h00;
            endcase
        end
    end

endmodule
