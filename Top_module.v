module Car_Simulator_Top (
    input CLK,              // 50MHz Clock
    
    // 키패드 버튼 1:1 직접 입력 (Pin Planner에서 핀 할당)
    input KEY_1,     // 경적
    input KEY_2,     // 핸들 리셋 (미사용시 연결만)
    input KEY_3,     // P (주차)
    input KEY_4,     // 좌회전 (미사용시 연결만)
    input KEY_5,     // 우회전 (미사용시 연결만)
    input KEY_6,     // R (후진)
    input KEY_7,     // 급브레이크
    input KEY_8,     // 시스템 리셋
    input KEY_9,     // N (중립)
    input KEY_STAR,  // * (일반 브레이크)
    input KEY_0,     // 시동 버튼
    input KEY_SHARP, // # (D 주행)
    
    // 스위치 & 가속페달(ADC)
    input [7:0] DIP_SW,     // SW1~8 (SW1:깜빡이L, SW2:깜빡이R, SW3:비상등, SW4:전조등, SW5:상향등, SW7:사이드, SW8:OBD)
    
    // SPI ADC (가속페달, 조도센서)
    output SPI_SCK, 
    output SPI_AD, 
    output SPI_DIN, 
    input SPI_DOUT,
    
    // 출력 포트
    output [7:0] SEG_DATA, // 8-Digit Segment Data
    output [7:0] SEG_COM,  // 8-Digit Segment Common
    output PIEZO,          // 부저
    output [7:0] LED,      // LED 1~8
    output LCD_RS, LCD_RW, LCD_E, output [7:0] LCD_DATA, // LCD
    
    // 전조등 (Full Color LED)
    output [3:0] FC_RED, 
    output [3:0] FC_GREEN, 
    output [3:0] FC_BLUE,
    
    // 1-Digit Segment (기어 표시)
    output [7:0] SEG_1_DATA
);

    // 내부 신호 정의
    wire tick_1s, tick_spd, tick_scn, tick_snd;
    wire [7:0] spd_w, fuel_w, temp_w, adc_accel_w, adc_cds_w;
    wire [13:0] rpm_w;
    wire [31:0] odo_w;
    wire ess_trig, led_l, led_r;
    wire engine_on_w; // 시동 상태 신호
    
    reg [3:0] gear_reg;

    // ★ [안전 리셋 로직]
    // 조건: (8번키) + (속도0) + (기어P) + (브레이크*) + (OBD모드 SW8)
    wire global_safe_rst;
    assign global_safe_rst = (KEY_8 && (spd_w == 0) && (gear_reg == 4'd3) && KEY_STAR && DIP_SW[7]); 

    // =========================================================
    // 1. 클럭 생성기
    // =========================================================
    Clock_Gen u_clk (
        .clk(CLK), 
        .rst(global_safe_rst),
        .tick_1sec(tick_1s), 
        .tick_speed(tick_spd), 
        .tick_scan(tick_scn), 
        .tick_sound(tick_snd)
    );
    
    // =========================================================
    // 2. SPI ADC (악셀, 조도센서)
    // =========================================================
    SPI_ADC_Controller u_adc (
        .clk(CLK), 
        .rst(global_safe_rst),
        .spi_sck(SPI_SCK), 
        .spi_cs_n(SPI_AD), 
        .spi_mosi(SPI_DIN), 
        .spi_miso(SPI_DOUT), 
        .adc_accel(adc_accel_w), 
        .adc_cds(adc_cds_w)
    );
    
    // =========================================================
    // 3. 기어 변경 로직 (직관적 입력 KEY_x 사용)
    // =========================================================
    always @(posedge CLK or posedge global_safe_rst) begin
        if (global_safe_rst) gear_reg <= 4'd3; // 초기값 P
        else begin
            if (KEY_3) gear_reg <= 4'd3;      // 3번: P
            else if (KEY_6) gear_reg <= 4'd6; // 6번: R
            else if (KEY_9) gear_reg <= 4'd9; // 9번: N
            else if (KEY_SHARP) gear_reg <= 4'd12; // #번: D
        end
    end

    // =========================================================
    // 4. 차량 로직 (Vehicle Logic) - 시동 로직 포함
    // =========================================================
    Vehicle_Logic u_logic (
        .clk(CLK), 
        .rst(global_safe_rst),
        .tick_1sec(tick_1s), 
        .tick_speed(tick_spd), 
        .current_gear(gear_reg), 
        .adc_accel(adc_accel_w), 
        .is_brake_normal(KEY_STAR), // *번: 일반브레이크
        .is_brake_hard(KEY_7),      // 7번: 급브레이크
        .is_start_btn(KEY_0),       // 0번: 시동 버튼
        
        .engine_on(engine_on_w),    // 시동 상태 출력 -> 다른 모듈로 전달
        .speed(spd_w), 
        .rpm(rpm_w), 
        .fuel(fuel_w), 
        .temp(temp_w), 
        .odometer_raw(odo_w), 
        .ess_trigger(ess_trig)
    );

    // =========================================================
    // 5. 방향지시등
    // =========================================================
    Turn_Signal_Logic u_sig (
        .clk(CLK), 
        .rst(global_safe_rst), 
        .sw_left(DIP_SW[0]), 
        .sw_right(DIP_SW[1]), 
        .sw_hazard(DIP_SW[2]), 
        .ess_active(ess_trig), 
        .led_left(led_l), 
        .led_right(led_r)
    );

    // =========================================================
    // 6. 라이트 컨트롤러 (전조등, 후미등, 오토라이트)
    // =========================================================
    Light_Controller u_light (
        .clk(CLK), 
        .rst(global_safe_rst),
        .engine_on(engine_on_w),    // 시동 켜져야 불 들어옴
        .current_gear(gear_reg),    // 후진등용 기어 정보
        .sw_headlight(DIP_SW[3]),   // SW4
        .sw_high_beam(DIP_SW[4]),   // SW5
        .cds_val(adc_cds_w), 
        .is_brake(KEY_7 | KEY_STAR), 
        .turn_left(led_l), 
        .turn_right(led_r),
        
        .fc_red(FC_RED), 
        .fc_green(FC_GREEN), 
        .fc_blue(FC_BLUE),
        .led_port(LED)
    );

    // =========================================================
    // 7. 디스플레이 (7-Segment) - BCD 적용됨
    // =========================================================
    Display_Unit u_disp (
        .clk(CLK), 
        .rst(global_safe_rst),
        .tick_scan(tick_scn), 
        .obd_mode_sw(DIP_SW[7]), 
        .engine_on(engine_on_w),    // 시동 꺼지면 화면 끔
        .rpm(rpm_w), 
        .speed(spd_w), 
        .fuel(fuel_w), 
        .temp(temp_w), 
        .gear_char(gear_reg), 
        .seg_data(SEG_DATA), 
        .seg_com(SEG_COM), 
        .seg_1_data(SEG_1_DATA)
    );

    // =========================================================
    // 8. LCD 모듈
    // =========================================================
    LCD_Module u_lcd (
        .clk(CLK), 
        .rst(global_safe_rst), 
        .engine_on(engine_on_w),    // 시동 꺼지면 OFF 메시지
        .odometer(odo_w), 
        .fuel(fuel_w), 
        .is_side_brake(DIP_SW[6]), 
        .lcd_rs(LCD_RS), 
        .lcd_rw(LCD_RW), 
        .lcd_e(LCD_E), 
        .lcd_data(LCD_DATA)
    );

    // =========================================================
    // 9. 사운드 유닛 (엔진음 제거, 깜빡이 개선)
    // =========================================================
    Sound_Unit u_snd (
        .clk(CLK), 
        .rst(global_safe_rst), 
        .is_horn(KEY_1),                // 1번: 경적
        .turn_signal_pulse(led_l | led_r), // 깜빡이 신호 (반복 펄스)
        .piezo_out(PIEZO)
    );

endmodule