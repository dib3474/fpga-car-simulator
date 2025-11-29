module Clock_Gen (
    input clk,              // 50MHz
    input rst,
    output reg tick_1sec = 0,   // 1초
    output reg tick_speed = 0,  // 속도 연산 (0.05초)
    output reg tick_scan = 0    // 7-Seg 스캔 (1ms)
);

    reg [25:0] cnt_1sec = 0;
    reg [21:0] cnt_speed = 0; 
    reg [15:0] cnt_scan = 0;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cnt_1sec <= 0; cnt_speed <= 0; cnt_scan <= 0;
            tick_1sec <= 0; tick_speed <= 0; tick_scan <= 0;
        end else begin
            // 1초 Tick
            if (cnt_1sec >= 50_000_000 - 1) begin
                cnt_1sec <= 0; tick_1sec <= 1;
            end else begin
                cnt_1sec <= cnt_1sec + 1; tick_1sec <= 0;
            end

            // 속도 연산 Tick
            if (cnt_speed >= 2_500_000 - 1) begin
                cnt_speed <= 0; tick_speed <= 1;
            end else begin
                cnt_speed <= cnt_speed + 1; tick_speed <= 0;
            end

            // 스캔 Tick
            if (cnt_scan >= 50_000 - 1) begin
                cnt_scan <= 0; tick_scan <= 1;
            end else begin
                cnt_scan <= cnt_scan + 1; tick_scan <= 0;
            end
        end
    end
endmodule
