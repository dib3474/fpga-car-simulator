module Clock_Gen (
    input clk, input rst,
    output reg tick_1sec, output reg tick_speed, output reg tick_scan, output reg tick_sound
);
    reg [25:0] cnt_1sec; reg [20:0] cnt_speed; reg [15:0] cnt_scan;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin 
            cnt_1sec<=0; cnt_speed<=0; cnt_scan<=0; 
            tick_1sec<=0; tick_speed<=0; tick_scan<=0; 
        end else begin
            if (cnt_1sec >= 50_000_000 - 1) begin cnt_1sec<=0; tick_1sec<=1; end 
            else begin cnt_1sec<=cnt_1sec+1; tick_1sec<=0; end

            if (cnt_speed >= 2_500_000 - 1) begin cnt_speed<=0; tick_speed<=1; end 
            else begin cnt_speed<=cnt_speed+1; tick_speed<=0; end

            if (cnt_scan >= 50_000 - 1) begin cnt_scan<=0; tick_scan<=1; end 
            else begin cnt_scan<=cnt_scan+1; tick_scan<=0; end
        end
    end
endmodule