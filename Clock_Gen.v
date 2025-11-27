module Clock_Gen (
    input clk,              // 50MHz
    input rst,
    output reg tick_1sec,   // 1초 (거리, 연료용)
    output reg tick_speed,  // 속도 갱신용 (약 0.05초)
    output reg tick_scan,   // 7-Seg 스캔용 (약 1ms)
    output reg tick_sound   // 소리용 (사용 안할수도 있음)
);

    reg [25:0] cnt_1sec;
    reg [20:0] cnt_speed;
    reg [15:0] cnt_scan;

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

            // 속도 갱신 Tick
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