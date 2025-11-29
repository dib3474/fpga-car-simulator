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
    // 1-Digit COM은 그라운드 (Display_Unit 내부 처리)
    output SERVO_PWM,
    output [3:0] FC_RED, output [3:0] FC_GREEN, output [3:0] FC_BLUE
);

    // ... (내부 와이어 선언 생략) ...
    wire tick_1s, tick_spd, tick_scn, tick_snd;
    
    wire [7:0] spd_w, fuel_w, temp_w, adc_accel_w, adc_cds_w;
    wire [13:0] rpm_w;
    wire [31:0] odo_w;
    wire ess_trig, led_l, led_r;
    wire accel_active;
    reg [3:0] gear_reg = 4'd3;
    reg engine_on = 1'b0;

    // 리셋 로직
    wire global_safe_rst;
    assign global_safe_rst = (KEY_8 && (spd_w == 0) && (gear_reg == 4'd3) && KEY_STAR && DIP_SW[7]); 

    // --- 클럭 생성 ---
    Clock_Gen u_clk (.clk(CLK), .rst(global_safe_rst), .tick_1sec(tick_1s), .tick_speed(tick_spd), .tick_scan(tick_scn), .tick_sound(tick_snd));
    SPI_ADC_Controller u_adc (.clk(CLK), .rst(global_safe_rst), .spi_sck(SPI_SCK), .spi_cs_n(SPI_AD), .spi_mosi(SPI_DIN), .spi_miso(SPI_DOUT), .adc_accel(adc_accel_w), .adc_cds(adc_cds_w));

    assign accel_active = (adc_accel_w > 8'd10);
    
    // Warning Light Logic (ESS Timer)
    wire ess_active_wire;
    Warning_Light_Logic u_warn (
        .clk(CLK), .rst(global_safe_rst), .tick_1sec(tick_1s),
        .sw_hazard(DIP_SW[2]), .ess_trigger(ess_trig), 
        .is_accel_pressed(accel_active),
        .blink_out(), 
        .ess_active_out(ess_active_wire)
    );

    // --- 시동 로직 (Debounce 적용) ---
    // 시동 조건: P단(KEY_3) + 브레이크(KEY_STAR) + 시동버튼(KEY_0)
    // 시동 끄기: P단 + 시동버튼(KEY_0) (브레이크 없이)
    
    reg [3:0] start_debounce_cnt;
    reg prev_key_0;
    
    always @(posedge CLK or posedge global_safe_rst) begin
        if (global_safe_rst) begin
            engine_on <= 1'b0;
            start_debounce_cnt <= 0;
            prev_key_0 <= 0;
        end else if (tick_spd) begin // 50ms 주기
            prev_key_0 <= KEY_0;
            
            // KEY_0(시동버튼)이 눌린 순간 (Rising Edge)
            if (KEY_0 && !prev_key_0) begin
                if (engine_on) begin
                    // 시동 끄기: 속도 0일 때만 가능
                    if (spd_w == 0) engine_on <= 1'b0;
                end else begin
                    // 시동 켜기: P단 + 브레이크(KEY_STAR) + 속도 0
                    if (gear_reg == 4'd3 && KEY_STAR && spd_w == 0) engine_on <= 1'b1;
                end
            end
        end
    end

    // --- 기어 변경 로직 ---
    always @(posedge CLK or posedge global_safe_rst) begin
        if (global_safe_rst) gear_reg <= 4'd3;
        else begin
            // 시동 켜진 상태에서만 기어 변경 가능 (안전)
            // 또는 시동 꺼져도 P단으로는 갈 수 있게? -> 보통은 시동 켜야 기어 바꿈
            if (KEY_3) gear_reg <= 4'd3;      // P
            else if (KEY_6) gear_reg <= 4'd6; // R
            else if (KEY_9) gear_reg <= 4'd9; // N
            else if (KEY_SHARP) gear_reg <= 4'd12; // D
        end
    end

    Vehicle_Logic u_logic (.clk(CLK), .rst(global_safe_rst), .engine_on(engine_on), .tick_1sec(tick_1s), .tick_speed(tick_spd), .current_gear(gear_reg), .adc_accel(adc_accel_w), .is_brake_normal(KEY_STAR), .is_brake_hard(KEY_7), .speed(spd_w), .rpm(rpm_w), .fuel(fuel_w), .temp(temp_w), .odometer_raw(odo_w), .ess_trigger(ess_trig));
    
    // --- LED & LCD 제어 (시동 상태 반영) ---
    // 시동 꺼짐(engine_on=0): LED, LCD 모두 OFF (단, 비상등은 켜질 수 있음)
    // 시동 켜짐(engine_on=1): 정상 동작
    
    wire [7:0] led_logic_out;
    wire [7:0] lcd_data_logic;
    wire lcd_rs_logic, lcd_rw_logic, lcd_e_logic;
    
    Turn_Signal_Logic u_sig (.clk(CLK), .rst(global_safe_rst), .sw_left(DIP_SW[0]), .sw_right(DIP_SW[1]), .sw_hazard(DIP_SW[2]), .ess_active(ess_active_wire), .led_left(led_l), .led_right(led_r));
    Light_Controller u_light (.clk(CLK), .rst(global_safe_rst), .sw_headlight(DIP_SW[3]), .sw_high_beam(DIP_SW[4]), .cds_val(adc_cds_w), .is_brake(KEY_7 | KEY_STAR), .turn_left(led_l), .turn_right(led_r), .fc_red(FC_RED), .fc_green(FC_GREEN), .fc_blue(FC_BLUE), .led_port(led_logic_out));

    // LED: 시동 꺼져도 비상등(Hazard)은 켜져야 함. 나머지는 OFF.
    assign LED = (engine_on) ? led_logic_out : (DIP_SW[2] ? led_logic_out : 8'b0);

    // Display Unit: 시동 꺼지면 꺼짐 (또는 P단만 표시?) -> 여기선 다 끄거나 0000 표시
    // 시동 꺼지면 seg_data를 0으로? -> Display_Unit 내부에서 engine_on 처리 필요할 수도 있지만
    // 여기서는 간단하게 engine_on이 0이면 입력을 0으로 줘서 0000 뜨게 하거나 아예 끄는게 나음.
    // 하지만 Display_Unit은 engine_on 입력이 없으므로, rst를 활용하거나 입력을 0으로 만듦.
    
    Display_Unit u_disp (
        .clk(CLK), 
        .rst(global_safe_rst), 
        .tick_scan(tick_scn), .obd_mode_sw(DIP_SW[7]), 
        .rpm(engine_on ? rpm_w : 14'd0), 
        .speed(engine_on ? spd_w : 8'd0), 
        .fuel(engine_on ? fuel_w : 8'd0), 
        .temp(engine_on ? temp_w : 8'd0), 
        .gear_char(gear_reg), // 기어는 시동 꺼져도 P에 있으면 P라고 뜨는게 맞음 (ACC 모드 느낌)
        .seg_data(SEG_DATA), .seg_com(SEG_COM), .seg_1_data(SEG_1_DATA)
    );

    // LCD: 시동 꺼지면 Backlight OFF (데이터 0)
    LCD_Module u_lcd (.clk(CLK), .rst(global_safe_rst), .odometer(odo_w), .fuel(fuel_w), .is_side_brake(DIP_SW[6]), .lcd_rs(lcd_rs_logic), .lcd_rw(lcd_rw_logic), .lcd_e(lcd_e_logic), .lcd_data(lcd_data_logic));
    
    assign LCD_RS = engine_on ? lcd_rs_logic : 0;
    assign LCD_RW = engine_on ? lcd_rw_logic : 0;
    assign LCD_E  = engine_on ? lcd_e_logic  : 0;
    assign LCD_DATA = engine_on ? lcd_data_logic : 8'b0;

    Servo_Controller u_servo (.clk(CLK), .rst(global_safe_rst), .speed(spd_w), .servo_pwm(SERVO_PWM));
    Sound_Unit u_snd (.clk(CLK), .rst(global_safe_rst), .rpm(rpm_w), .ess_active(led_l | led_r), .is_horn(KEY_1), .turn_signal_on(led_l | led_r), .engine_on(engine_on), .accel_active(accel_active), .piezo_out(PIEZO));

endmodule
