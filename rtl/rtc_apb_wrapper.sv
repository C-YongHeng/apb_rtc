module rtc_apb_wrapper
#(
    parameter APB_ADDR_WIDTH = 12
)(
    input PCLK,
    input PRESETn,

    input [APB_ADDR_WIDTH-1:0] PADDR,
    input [31:0] PWDATA,
    input PWRITE,
    input PSEL,
    input PENABLE,
    output [31:0] PRDATA,
    output PREADY,
    output PSLVERR,

    input rtc_clk_i,
    input rtc_rstn_i,
    output rtc_irq_o
);

    localparam RTC_DATE_OFFSET = 8'h00;
    localparam RTC_CLOCK_OFFSET = 8'h04;
    localparam RTC_ALARM_DATE_OFFSET = 8'h08;
    localparam RTC_ALARM_CLOCK_OFFSET = 8'h0c;
    localparam RTC_TIMER_OFFSET = 8'h10;
    localparam RTC_CALIBRE_OFFSET = 8'h14;
    localparam RTC_EVENT_FLAG_OFFSET = 8'h18;
    /* Register Mapping
     * RTC_DATE: WR
     * | 31:30 | 29:16 | 15:13 | 12:8 | 7:6 | 5:0 |
     * | Res   | year  | Res   | mon  | Res | day |
     * -------------------------------------------
     * RTC_CLOCK: W
     * | 31:22 | 21:16 | 15:8 | 7:0 |
     * | cnt   | hours | mins | secs|
     * RTC_CLOCK: R
     * | 31:22 | 21:16 | 15:8 | 7:0 |
     * | Res   | hours | mins | secs|
     * -------------------------------------------
     * RTC_ALARM_DATE: WR
     * | 31:30 | 29:16 | 15:13 | 12:8 | 7:6 | 5:0 |
     * | Res   | year  | Res   | mon  | Res | day |
     * -------------------------------------------
     * RTC_ALARM_CLOCK: W
     * | 31 | 30:25 | 24:22 | 21:16 | 15:8 | 7:0 |
     * | en | mask  | Res   | hours | mins | secs|
     * RTC_ALARM_CLOCK: R
     * | 31:22 | 21:16 | 15:8 | 7:0 |
     * | Res   | hours | mins | secs|
     * -------------------------------------------
     * RTC_TIMER: W
     * | 31 |  30  | 29:17 |  16:0   |
     * | en | retr | Res   | target  |
     * RTC_TIMER: R
     * | 31:17 |  16:0   |
     * | Res   | timercnt|
     * -------------------------------------------
     * RTC_CALIBRE: WR
     * | 31:16 |   15:0   |
     * | Res   | sec_ratio|
     * -------------------------------------------
     * RTC_EVENT_FLAG: R/W0
     * | 31:2 |         1   |      0      |
     * | Res  | timer_event | alarm_event |
    */
    logic [31:0] prdata_in_pclk;
    logic pready_in_pclk, pready_syn, pready_in_rtc_clk;
    logic apb_write_en, apb_write_en_r;
    logic apb_write_en_pulse, apb_write_en_pulse_syn1, apb_write_en_pulse_syn2, apb_write_en_pulse_syn3;
    logic apb_write_en_pulse_in_rtc_clock;
    logic apb_write_en_in_rtc_clock;
    logic [7:0] apb_write_addr_in_rtc_clock;
    logic [31:0] apb_write_data_in_rtc_clock;


    logic rtc_date_update_en;
    logic [31:0] rtc_date_update_data;
    logic rtc_clock_update_en;
    logic [21:0] rtc_clock_update_data;
    logic [9:0] rtc_init_sec_cnt_update_data;
    logic rtc_calibre_update_en;
    logic [15:0] rtc_calibre_sec_cnt_update_data;
    logic rtc_timer_update_en;
    logic rtc_timer_enable;
    logic rtc_timer_retrig;
    logic [16:0] rtc_timer_target;

    logic rtc_alarm_update_clock_en;
    logic [21:0] rtc_alarm_clock_update_data;
    logic rtc_alarm_enable;
    logic [5:0] rtc_alarm_mask;
    logic rtc_alarm_update_date_en;
    logic [31:0] rtc_alarm_date_update_data;
    logic rtc_event_flag_update_en;
    logic [1:0] rtc_event_flag_update_data;


    logic [31:0] rtc_date_data, rtc_date_data_syn;
    logic [21:0] rtc_clock_data, rtc_clock_data_syn;
    logic [15:0] rtc_calibre_sec_cnt_data, rtc_calibre_sec_cnt_data_syn;
    logic [16:0] rtc_timer_value, rtc_timer_value_syn;
    logic [21:0] rtc_alarm_clock_data, rtc_alarm_clock_data_syn;
    logic [31:0] rtc_alarm_date_data, rtc_alarm_date_data_syn;
    logic [1:0] rtc_event_flag_data, rtc_event_flag_data_syn;
    logic rtc_event, rtc_event_syn;

    always @(posedge PCLK, negedge PRESETn) begin
        if(!PRESETn) begin
            rtc_date_data_syn <= '0;
            rtc_clock_data_syn <= '0;
            rtc_calibre_sec_cnt_data_syn <= '0;
            rtc_timer_value_syn <= '0;
            rtc_alarm_clock_data_syn <= '0;
            rtc_alarm_date_data_syn <= '0;
            rtc_event_flag_data_syn <= '0;
            rtc_event_syn <= '0;
        end else begin
            rtc_date_data_syn <= rtc_date_data;
            rtc_clock_data_syn <= rtc_clock_data;
            rtc_calibre_sec_cnt_data_syn <= rtc_calibre_sec_cnt_data;
            rtc_timer_value_syn <= rtc_timer_value;
            rtc_alarm_clock_data_syn <= rtc_alarm_clock_data;
            rtc_alarm_date_data_syn <= rtc_alarm_date_data;
            rtc_event_flag_data_syn <= rtc_event_flag_data;
            rtc_event_syn <= rtc_event;
        end
    end

    // APB write syn
    assign apb_write_en = PSEL & PENABLE & PWRITE;
    assign apb_write_en_pulse = apb_write_en & (~apb_write_en_r);
    always @(posedge PCLK, negedge PRESETn) begin
        if(!PRESETn) begin
            apb_write_en_r <= 1'b0;
            pready_in_pclk <= 1'b0;
            pready_syn <= 1'b0;
        end else begin
            apb_write_en_r <= apb_write_en;
            pready_in_pclk <= pready_syn;
            pready_syn <= pready_in_rtc_clk;
        end
    end

    // 2-stage pulse syn
    always @(posedge rtc_clk_i) begin
        apb_write_en_pulse_syn1 <= apb_write_en_pulse;
        apb_write_en_pulse_syn2 <= apb_write_en_pulse_syn1;
        apb_write_en_pulse_syn3 <= apb_write_en_pulse_syn2;
    end
    assign apb_write_en_pulse_in_rtc_clock = apb_write_en_pulse_syn2 & ~apb_write_en_pulse_syn3;

    always @(posedge rtc_clk_i, negedge rtc_rstn_i) begin
        if(!rtc_rstn_i) begin
            apb_write_addr_in_rtc_clock <= '0;
            apb_write_data_in_rtc_clock <= '0;
            pready_in_rtc_clk <= '0;
        end else begin
            if(apb_write_en_pulse_in_rtc_clock) begin
                apb_write_en_in_rtc_clock <= 1'b1;
                apb_write_addr_in_rtc_clock <= PADDR[7:0];
                apb_write_data_in_rtc_clock <= PWDATA[31:0];
                pready_in_rtc_clk <= '1;
            end else begin
                apb_write_en_in_rtc_clock <= 1'b0;
                pready_in_rtc_clk <= '0;
            end
        end
    end

    // write logic
    always_comb begin
        rtc_date_update_en = '0;
        rtc_date_update_data = '0;
        rtc_clock_update_en = '0;
        rtc_clock_update_data = '0;
        rtc_init_sec_cnt_update_data = '0;
        rtc_alarm_update_date_en = '0;
        rtc_alarm_date_update_data = '0;
        rtc_alarm_update_clock_en = '0;
        rtc_alarm_clock_update_data = '0;
        rtc_alarm_enable = '0;
        rtc_alarm_mask = '0;
        rtc_timer_update_en = '0;
        rtc_timer_enable = '0;
        rtc_timer_retrig = '0;
        rtc_timer_target = '0;
        rtc_calibre_update_en = '0;
        rtc_calibre_sec_cnt_update_data = '0;
        rtc_event_flag_update_en = '0;
        rtc_event_flag_update_data = '0;
        case (apb_write_addr_in_rtc_clock)
            RTC_DATE_OFFSET: begin
                rtc_date_update_en = apb_write_en_in_rtc_clock;
                rtc_date_update_data = apb_write_data_in_rtc_clock;
            end
            RTC_CLOCK_OFFSET: begin
                rtc_clock_update_en = apb_write_en_in_rtc_clock;
                rtc_clock_update_data = apb_write_data_in_rtc_clock[21:0];
                rtc_init_sec_cnt_update_data = apb_write_data_in_rtc_clock[31:22];
            end
            RTC_ALARM_DATE_OFFSET: begin
                rtc_alarm_update_date_en = apb_write_en_in_rtc_clock;
                rtc_alarm_date_update_data = apb_write_data_in_rtc_clock[31:0];
            end
            RTC_ALARM_CLOCK_OFFSET: begin
                rtc_alarm_update_clock_en = apb_write_en_in_rtc_clock;
                rtc_alarm_clock_update_data = apb_write_data_in_rtc_clock[21:0];
                rtc_alarm_enable = apb_write_data_in_rtc_clock[31];
                rtc_alarm_mask = apb_write_data_in_rtc_clock[30:25];
            end
            RTC_TIMER_OFFSET: begin
                rtc_timer_update_en = apb_write_en_in_rtc_clock;
                rtc_timer_enable = apb_write_data_in_rtc_clock[31];
                rtc_timer_retrig = apb_write_data_in_rtc_clock[30];
                rtc_timer_target = apb_write_data_in_rtc_clock[16:0];
            end
            RTC_CALIBRE_OFFSET: begin
                rtc_calibre_update_en = apb_write_en_in_rtc_clock;
                rtc_calibre_sec_cnt_update_data = apb_write_data_in_rtc_clock[15:0];
            end
            RTC_EVENT_FLAG_OFFSET: begin
                rtc_event_flag_update_en = apb_write_en_in_rtc_clock;
                rtc_event_flag_update_data = apb_write_data_in_rtc_clock[1:0];
            end
            default: begin
            end
        endcase
    end



    // APB read
    always_comb begin
        case (PADDR[7:0])
            RTC_DATE_OFFSET:
                prdata_in_pclk = rtc_date_data_syn;
            RTC_CLOCK_OFFSET:
                prdata_in_pclk = {10'b0, rtc_clock_data_syn};
            RTC_ALARM_DATE_OFFSET:
                prdata_in_pclk = rtc_alarm_date_data_syn;
            RTC_ALARM_CLOCK_OFFSET:
                prdata_in_pclk = {10'b0, rtc_alarm_clock_data_syn};
            RTC_TIMER_OFFSET:
                prdata_in_pclk = {15'b0, rtc_timer_value_syn};
            RTC_CALIBRE_OFFSET:
                prdata_in_pclk = {16'b0, rtc_calibre_sec_cnt_data_syn};
            RTC_EVENT_FLAG_OFFSET:
                prdata_in_pclk = {30'b0, rtc_event_flag_data_syn};
            default: 
                prdata_in_pclk = 32'b0;
        endcase
    end


    rtc_top i_trc_top(
        .clk_i(rtc_clk_i),
        .rstn_i(rtc_rstn_i),

        .date_update_i(rtc_date_update_en),
        .date_i(rtc_date_update_data),
        .date_o(rtc_date_data),

        .clock_update_i(rtc_clock_update_en),
        .clock_i(rtc_clock_update_data),
        .init_sec_cnt_i(rtc_init_sec_cnt_update_data), // sec_timer init value
        .clock_o(rtc_clock_data),

        .calibre_update_i(rtc_calibre_update_en),
        .calibre_sec_cnt_i(rtc_calibre_sec_cnt_update_data), // sec_timer cmp value
        .calibre_sec_cnt_o(rtc_calibre_sec_cnt_data),

        .timer_update_i(rtc_timer_update_en),
        .timer_enable_i(rtc_timer_enable),
        .timer_retrig_i(rtc_timer_retrig), // is retrigger
        .timer_target_i(rtc_timer_target), // timer target
        .timer_value_o(rtc_timer_value), // timer value

        .alarm_update_clock_i(rtc_alarm_update_clock_en),
        .alarm_enable_i(rtc_alarm_enable),
        .alarm_mask_i(rtc_alarm_mask),
        .alarm_clock_i(rtc_alarm_clock_update_data),
        .alarm_clock_o(rtc_alarm_clock_data),

        .alarm_update_date_i(rtc_alarm_update_date_en),
        .alarm_date_i(rtc_alarm_date_update_data),
        .alarm_date_o(rtc_alarm_date_data),

        .event_flag_update_i(rtc_event_flag_update_en),
        .event_flag_i(rtc_event_flag_update_data),
        .event_flag_o(rtc_event_flag_data),
        .event_o(rtc_event)

    );

    assign rtc_irq_o = rtc_event_syn;
    assign PRDATA = prdata_in_pclk;
    assign PSLVERR = 1'b0;
    assign PREADY = pready_in_pclk | (PSEL & ~PWRITE & PENABLE);

endmodule
