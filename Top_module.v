module Car_Simulator_Top (
    input CLK,
    // 키패드
    input KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6,
    input KEY_7, KEY_8, KEY_9, KEY_STAR, KEY_0, KEY_SHARP,
    // 스위치 & ADC
    input [7:0] DIP_SW,
    output SPI_SCK, SPI_AD, SPI_DIN, input SPI_DOUT,
    // 출력
    output [7:0] SEG_DATA, SEG_COM,
    output PIEZO,
    output [7:0] LED,
    output LCD_RS, LCD_RW, LCD_E, output [7:0] LCD_DATA,
    output [7:0] SEG_1_DATA, // 1-Digit 데이터
    // 1-Digit COM은 삭제됨 (Display_Unit 수정 반영)
    
    output [3:0] FC_RED, output [3:0] FC_GREEN, output [3:0] FC_BLUE
);

    // ... (내부 와이어 선언 동일) ...
    wire tick_1s, tick_spd, tick_scn, tick_snd;
    wire [7:0] spd_w, fuel_w, temp_w, adc_accel_w, adc_cds_w;
    wire [13:0] rpm_w;
    wire [31:0] odo_w;
    wire ess_trig, led_l, led_r;
    reg [3:0] gear_reg;

    // 안전 리셋
    wire global_safe_rst;
    assign global_safe_rst = (KEY_8 && (spd_w == 0) && (gear_reg == 4'd3) && KEY_STAR && DIP_SW[7]); 

    // --- 모듈 연결 ---
    Clock_Gen u_clk (.clk(CLK), .rst(global_safe_rst), .tick_1sec(tick_1s), .tick_speed(tick_spd), .tick_scan(tick_scn), .tick_sound(tick_snd));
    SPI_ADC_Controller u_adc (.clk(CLK), .rst(global_safe_rst), .spi_sck(SPI_SCK), .spi_cs_n(SPI_AD), .spi_mosi(SPI_DIN), .spi_miso(SPI_DOUT), .adc_accel(adc_accel_w), .adc_cds(adc_cds_w));
    
    always @(posedge CLK or posedge global_safe_rst) begin
        if (global_safe_rst) gear_reg <= 4'd3;
        else begin
            if (KEY_3) gear_reg <= 4'd3; else if (KEY_6) gear_reg <= 4'd6;
            else if (KEY_9) gear_reg <= 4'd9; else if (KEY_SHARP) gear_reg <= 4'd12;
        end
    end

    Vehicle_Logic u_logic (.clk(CLK), .rst(global_safe_rst), .tick_1sec(tick_1s), .tick_speed(tick_spd), .current_gear(gear_reg), .adc_accel(adc_accel_w), .is_brake_normal(KEY_STAR), .is_brake_hard(KEY_7), .speed(spd_w), .rpm(rpm_w), .fuel(fuel_w), .temp(temp_w), .odometer_raw(odo_w), .ess_trigger(ess_trig));
    Turn_Signal_Logic u_sig (.clk(CLK), .rst(global_safe_rst), .sw_left(DIP_SW[0]), .sw_right(DIP_SW[1]), .sw_hazard(DIP_SW[2]), .ess_active(ess_trig), .led_left(led_l), .led_right(led_r));
    Light_Controller u_light (.clk(CLK), .rst(global_safe_rst), .sw_headlight(DIP_SW[3]), .sw_high_beam(DIP_SW[4]), .cds_val(adc_cds_w), .is_brake(KEY_7 | KEY_STAR), .turn_left(led_l), .turn_right(led_r), .fc_red(FC_RED), .fc_green(FC_GREEN), .fc_blue(FC_BLUE), .led_port(LED));

    // ★ Display Unit 연결 수정 (rst 포트 추가)
    Display_Unit u_disp (
        .clk(CLK), 
        .rst(global_safe_rst), // 리셋 연결!
        .tick_scan(tick_scn), .obd_mode_sw(DIP_SW[7]), 
        .rpm(rpm_w), .speed(spd_w), .fuel(fuel_w), .temp(temp_w), .gear_char(gear_reg), 
        .seg_data(SEG_DATA), .seg_com(SEG_COM), .seg_1_data(SEG_1_DATA)
    );

    LCD_Module u_lcd (.clk(CLK), .rst(global_safe_rst), .odometer(odo_w), .fuel(fuel_w), .is_side_brake(DIP_SW[6]), .lcd_rs(LCD_RS), .lcd_rw(LCD_RW), .lcd_e(LCD_E), .lcd_data(LCD_DATA));
    Sound_Unit u_snd (.clk(CLK), .rst(global_safe_rst), .rpm(rpm_w), .ess_active(led_l | led_r), .is_horn(KEY_1), .turn_signal_on(led_l | led_r), .piezo_out(PIEZO));

endmodule