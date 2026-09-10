
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;

library desyrdl;
use desyrdl.common.all;
use desyrdl.pkg_pl_regs.all;

library xil_defaultlib;
use xil_defaultlib.bpm_package.ALL;


entity top is
generic(
    FPGA_VERSION			: integer := 9;
    SIM_MODE				: integer := 0
    );
  port (  
    -- 2 dual adc I/O for LTC2195
    adc_csb                : out std_logic_vector(1 downto 0);
    adc_sdi                : out std_logic_vector(1 downto 0);
    adc_sdo                : in std_logic_vector(1 downto 0);
    adc_sclk               : out std_logic_vector(1 downto 0);   
    adc_fco_p              : in std_logic_vector(1 downto 0);
    adc_fco_n              : in std_logic_vector(1 downto 0); 
    adc_dco_p              : in std_logic_vector(1 downto 0);
    adc_dco_n              : in std_logic_vector(1 downto 0);   
    adc_sdata_p            : in std_logic_vector(15 downto 0);
    adc_sdata_n            : in std_logic_vector(15 downto 0);    

    -- adc clock input (from AD9510)
    adc_clk_p               : in std_logic;
    adc_clk_n               : in std_logic;
    
    -- tbt clock input
    tbt_clk_p               : in std_logic;
    tbt_clk_n               : in std_logic;
    
    -- evr rcvd clk to AD9510
    evr_rcvd_clk_p          : out std_logic;
    evr_rcvd_clk_n          : out std_logic;
    
    -- adc clock synthesizer (AD9510)
    ad9510_sclk             : out std_logic;
    ad9510_sdata            : out std_logic;
    ad9510_lat              : out std_logic;
    ad9510_func             : out std_logic;
    ad9510_status           : in std_logic;
    ad9510_sdo              : in std_logic;   
    
   -- rf digital attenuator
    dsa_clk                 : out std_logic;
    dsa_sdata               : out std_logic;
    dsa_latch               : out std_logic;   
    
   -- Thermistor Readback (LT2986)
    therm_sclk              : out std_logic;
    therm_sdo               : in std_logic;
    therm_sdi               : out std_logic;
    therm_csn               : out std_logic_vector(2 downto 0);
    therm_rstn              : out std_logic;   
    
   -- heat pump controller daughterboard DAC's (AD5754)
    heatdac_syncn           : out std_logic_vector(1 downto 0);
    heatdac_sclk            : out std_logic_vector(1 downto 0);  
    heatdac_sdin            : out std_logic_vector(1 downto 0);
    heatdac_sdo             : in std_logic_vector(1 downto 0); 
    heatdac_ldacn           : out std_logic_vector(1 downto 0);
    
    heatdac_clrn            : out std_logic;  
    heatdac_bin2s           : out std_logic;             
         

	-- afe power management
	afe_pwrenb              : out std_logic;
	afe_pwrflt              : in std_logic;

    --evr transceiver
    gth_evr_refclk_p        : in std_logic;
    gth_evr_refclk_n        : in std_logic;
    gth_evr_tx_p            : out std_logic;
    gth_evr_tx_n            : out std_logic;
    gth_evr_rx_p            : in std_logic;
    gth_evr_rx_n            : in std_logic;   
    
    -- afe switch signals
	afe_sw_rffe_p           : out std_logic;
	afe_sw_rffe_n           : out std_logic; 
    
    sfp_led                 : out std_logic_vector(11 downto 0);
    sfp_rxlos               : in std_logic_vector(5 downto 0);
    
    fp_in                   : in std_logic_vector(3 downto 0);
    fp_out                  : out std_logic_vector(3 downto 0);
    fp_led                  : out std_logic_vector(7 downto 0);
    dbg                     : out std_logic_vector(19 downto 0) 

  );
end top;
 

architecture behv of top is

  
  signal pl_clk0         : std_logic;
  signal pl_clk1         : std_logic;
  signal adc_clk         : std_logic;
  signal pl_resetn       : std_logic;
  signal pl_reset        : std_logic;
  signal ps_leds         : std_logic_vector(7 downto 0);
  
  signal m_axi4_m2s      : t_pl_regs_m2s;
  signal m_axi4_s2m      : t_pl_regs_s2m;
  
  signal adc_clk_in      : std_logic;
  signal adc_data        : t_adc_raw; 
  signal adc_data_dma    : t_adc_raw;
  signal adc_data_sw     : t_adc_raw;
  signal adc_dbg         : std_logic_vector(3 downto 0);
  
  signal adc_spi_we      : std_logic;
  signal adc_spi_wdata   : std_logic_vector(31 downto 0);
  signal adc_spi_rdata   : std_logic_vector(31 downto 0);
  signal adc_idly_wrval  : std_logic_vector(8 downto 0);
  signal adc_idly_wrstr  : std_logic_vector(15 downto 0);
  signal adc_idly_rdval  : std_logic_vector(8 downto 0);       
  signal adc_fco_dlystr  : std_logic_vector(1 downto 0);  
  
  signal reg_o_adcfifo   : t_reg_o_adc_fifo_rdout;
  signal reg_i_adcfifo   : t_reg_i_adc_fifo_rdout;
  signal reg_o_tbtfifo   : t_reg_o_tbt_fifo_rdout;
  signal reg_i_tbtfifo   : t_reg_i_tbt_fifo_rdout;

  
  signal reg_o_dsa       : t_reg_o_dsa;  
  signal reg_o_pll       : t_reg_o_pll;
  signal reg_i_pll       : t_reg_i_pll;
  signal reg_o_adc       : t_reg_o_adc_cntrl;
  signal reg_i_adc       : t_reg_i_adc_status; 
  signal reg_o_tbt       : t_reg_o_tbt;
  signal reg_o_dma       : t_reg_o_dma;
  signal reg_i_dma       : t_reg_i_dma;
  signal reg_o_evr       : t_reg_o_evr;
  signal reg_i_evr       : t_reg_i_evr;
  signal reg_o_therm     : t_reg_o_therm;
  signal reg_i_therm     : t_reg_i_therm;
  signal reg_o_swrffe    : t_reg_o_swrffe;
  
  signal tbt_data        : t_tbt_data;    
  signal sa_data         : t_sa_data;
  signal fa_data         : t_fa_data;
  
  signal sw_rffe_demux   : std_logic;
  signal sw_rffe_time    : std_logic;
  
  signal dma_adc_active  : std_logic;
  signal dma_adc_tdata   : std_logic_vector(63 downto 0);
  signal dma_adc_tkeep   : std_logic_vector(7 downto 0);
  signal dma_adc_tlast   : std_logic;
  signal dma_adc_tready  : std_logic;
  signal dma_adc_tvalid  : std_logic;
    
  signal dma_tbt_active  : std_logic;
  signal dma_tbt_tdata   : std_logic_vector(63 downto 0);
  signal dma_tbt_tkeep   : std_logic_vector(7 downto 0);
  signal dma_tbt_tlast   : std_logic;
  signal dma_tbt_tready  : std_logic;
  signal dma_tbt_tvalid  : std_logic;  
    
  signal dma_fa_active   : std_logic;
  signal dma_fa_tdata    : std_logic_vector(63 downto 0);
  signal dma_fa_tkeep    : std_logic_vector(7 downto 0);
  signal dma_fa_tlast    : std_logic;
  signal dma_fa_tready   : std_logic;
  signal dma_fa_tvalid   : std_logic;    
  
  signal evr_tbt_trig    : std_logic;
  signal evr_fa_trig     : std_logic;
  signal evr_sa_trig     : std_logic;
  signal evr_gps_trig    : std_logic;
  signal evr_dma_trig    : std_logic;  
  signal evr_ts          : std_logic_vector(63 downto 0); 
  signal evr_rcvd_clk    : std_logic;
  signal evr_ref_clk     : std_logic;
   
  signal tbt_extclk      : std_logic;  
  
  signal tbt_gate        : std_logic;
  signal tbt_trig        : std_logic;
  signal pt_trig         : std_logic;
  signal fa_trig         : std_logic;
  signal sa_trig         : std_logic;
  signal sa_trig_stretch : std_logic;
  signal ps_fpled_stretch: std_logic;
  signal dma_trig        : std_logic;
  signal dma_busy        : std_logic;
  
  signal ioc_access_led  : std_logic;




  attribute mark_debug     : string;
  --attribute mark_debug of reg_o: signal is "true";
  attribute mark_debug of dsa_clk: signal is "true";
  attribute mark_debug of dsa_sdata: signal is "true";
  attribute mark_debug of dsa_latch: signal is "true";  
  attribute mark_debug of adc_data: signal is "true";
  attribute mark_debug of adc_data_sw: signal is "true";
 

begin

afe_pwrenb <= '1';
reg_i_pll.locked <= not ad9510_status;


dbg(0) <= pl_clk0;
dbg(1) <= dma_busy; --'0'; --adc_fco_dlystr(0); --'0';
dbg(2) <= adc_dbg(1);  --psdone 
dbg(3) <= '0';
dbg(4) <= adc_dbg(2); -- adc_fco_bufg 
dbg(5) <= adc_dbg(3); --adc_fco_mmcm 
dbg(6) <= '0'; --gth_refclk_buf; --'0';
dbg(7) <= '0'; --gth_txusr_clk;
dbg(8) <= '0'; --gth_rxusr_clk;
dbg(9) <= evr_tbt_trig;
dbg(10) <= evr_fa_trig;
dbg(11) <= evr_sa_trig;
dbg(12) <= tbt_trig; 
dbg(13) <= fa_trig;
dbg(14) <= sa_trig;
dbg(15) <= tbt_extclk;
dbg(16) <= sw_rffe_demux; --fp_in(0);
dbg(17) <= sw_rffe_time; --fp_in(1);
dbg(18) <= fp_in(2);
dbg(19) <= fp_in(3);


fp_out(0) <= evr_tbt_trig; --fa_trig; --pl_clk0;
fp_out(1) <= tbt_extclk; --afe_sw_rffe_p; --evr_rcvd_clk; 
fp_out(2) <= tbt_trig; --adc_clk_in; --adc_clk; 
fp_out(3) <= evr_rcvd_clk; --sw_rffe_time; --evr_rcvd_clk; --tbt_extclk; --tbt_trig; 

fp_led(7) <= dma_adc_active;
fp_led(6) <= dma_tbt_active; 
fp_led(5) <= dma_fa_active; 
fp_led(4) <= dma_busy; 
fp_led(3) <= not ad9510_status;
fp_led(2) <= ioc_access_led; 
fp_led(1) <= '0';
fp_led(0) <= sa_trig_stretch;

sfp_led(0) <= evr_gps_trig;
sfp_led(11 downto 1) <= (others => '0');


adc_clk_inst  : IBUFDS  port map (O => adc_clk_in, I => adc_clk_p, IB => adc_clk_n); 
tbt_clk_inst  : IBUFDS  port map (O => tbt_extclk, I => tbt_clk_p, IB => tbt_clk_n); 

--evr_clk_inst : OBUFDS  generic map (IOSTANDARD => "LVDS", SLEW => "FAST") port map (O => evr_rcvd_clk_p,  OB => evr_rcvd_clk_n, I => evr_rcvd_clk);
evr_clk_inst : OBUFDS  generic map (IOSTANDARD => "LVDS", SLEW => "FAST") port map (O => evr_rcvd_clk_p,  OB => evr_rcvd_clk_n, I => evr_tbt_trig);



pl_reset <= not pl_resetn;




---- reads in ADC data
adc_inst: entity work.adc_ltc2195
  generic map (
    SIM_MODE => SIM_MODE
  )
  port map(
    sys_clk => pl_clk0,
    sys_rst => pl_reset,  
    reg_o => reg_o_adc,
	reg_i => reg_i_adc,                     
    adc_csb => adc_csb,
    adc_sdi => adc_sdi,
    adc_sdo => adc_sdo,
    adc_sclk => adc_sclk,     
    adc_fco_p => adc_fco_p, 
    adc_fco_n => adc_fco_n, 
    adc_dco_p => adc_dco_p, 
    adc_dco_n => adc_dco_n,    
    adc_sdata_p => adc_sdata_p, 
    adc_sdata_n => adc_sdata_n,   
    adc_clk_out => adc_clk,
    adc_data => adc_data,
    dbg => adc_dbg
    );     


rffe_switcher: entity work.rffe_switch 
  port map ( 
    rst => pl_reset, 
    clk => adc_clk, 
    tbt_trig => tbt_trig,
    fa_trig => fa_trig,
    reg_o => reg_o_swrffe, 
    adc_data_i => adc_data,
    adc_data_o => adc_data_sw,
    adc_data_dma => adc_data_dma,
    sw_rffe_p => afe_sw_rffe_p,
    sw_rffe_n => afe_sw_rffe_n,
    sw_rffe_demux => sw_rffe_demux,
    sw_rffe_time => sw_rffe_time
);



tbt_engine: entity work.tbt_dsp 
  port map( 
    rst => pl_reset, 
    clk => adc_clk, 
    adc_data => adc_data_sw, 
    tbt_trig => tbt_trig, 
    tbt_data => tbt_data,
    tbt_params => reg_o_tbt
);


sa_engine: entity work.sa_dsp
  port map(
    rst => pl_reset,
    clk => adc_clk,
    tbt_data => tbt_data,
    tbt_trig => tbt_trig,
    sa_trig => sa_trig, 
    sa_data => sa_data
);


fa_engine: entity work.fa_dsp
  port map(
    rst => pl_reset,
    clk => adc_clk,
    tbt_data => tbt_data,
    tbt_trig => tbt_trig,
    fa_data => fa_data,
    fa_cnt => open, 
    fa_trig => fa_trig
);






--AD9510 PLL: generates adc_clk
pll_spi: entity work.spi_ad9510 
  port map(
    clk => pl_clk0,
    reset => pl_reset,  
    reg_o => reg_o_pll,
    sclk => ad9510_sclk, 
	sdo	=> ad9510_sdo, 		
    sdi => ad9510_sdata,
    csb => ad9510_lat, 
    func => ad9510_func
  );  




therm_rdbk: entity work.ltc2986_spi 
  port map (
    clk => pl_clk0,                     
    reset => pl_reset, 
    reg_o => reg_o_therm,  
    reg_i => reg_i_therm,                    
    --we => therm_we, 
    --sel => therm_sel,
    --wrdata => therm_wrdata,
    --rddata => therm_rddata, 
    csn => therm_csn, 
    sck => therm_sclk,                    
    sdi => therm_sdi, 
    sdo => therm_sdo,
    rstn => therm_rstn             
  );    




--programmable attenuator for rf chain  
atten_pt: entity work.spi_pe43712 
  port map(
    clk => pl_clk0,                  
    reset => pl_reset, 
    reg_o => reg_o_dsa,                        
    sclk => dsa_clk,                         
    sdi => dsa_sdata, 
    csb => dsa_latch                   
  );    

reg_i_evr.ts_s <= evr_ts(63 downto 32);
reg_i_evr.ts_ns <= evr_ts(31 downto 0);

dmatrig: entity work.trig_logic
  port map (
    adc_clk => adc_clk,  
    reset => pl_reset, 
    reg_o => reg_o_dma,
    reg_i => reg_i_dma,
    evr_trig => evr_dma_trig, 
    dma_adc_active => dma_adc_active,
    dma_tbt_active => dma_tbt_active, 
    dma_fa_active => dma_fa_active,
    evr_ts => evr_ts,
    evr_ts_lat => open, --evr_ts_lat, 
    dma_busy => dma_busy,
    dma_trig => dma_trig
  );    



-- provides dsp trigger signals
dsp_trigs : entity work.dsp_cntrl 
  port map(
	adc_clk => adc_clk,               
	tbt_extclk => evr_tbt_trig, --tbt_extclk, --evr_tbt_trig, 
	reset => pl_reset,
	tbt_params => reg_o_tbt,
    inttrig_enb => reg_o_evr.event_src_sel,  
    evrsync_cnt => '0', 
    evr_fa_trig => evr_fa_trig,
    evr_sa_trig => evr_sa_trig,       			
	tbt_gate => tbt_gate,
    tbt_trig => tbt_trig,
    pt_trig => pt_trig,
	fa_trig => fa_trig, 
    sa_trig => sa_trig, 
    sa_count => open --sa_cnt
  );  


adcstream:  entity work.adc2fifo
  port map(
    adc_clk => adc_clk,
    sys_clk => pl_clk0, 
    reset => pl_reset,   
  	reg_o => reg_o_adcfifo,
	reg_i => reg_i_adcfifo,  
    tbt_trig => sw_rffe_time, --tbt_trig,                     
	adc_data => adc_data
);    


tbtstream: entity work.tbt2fifo
  port map(
    adc_clk => adc_clk,
    sys_clk => pl_clk0, 
    reset => pl_reset,  
    reg_o => reg_o_tbtfifo,
	reg_i => reg_i_tbtfifo,                         
	tbt_data => tbt_data,
	tbt_trig => tbt_trig
);    


adctoddr: entity work.adc2dma
  port map(
    sys_clk => pl_clk1, 
    adc_clk => adc_clk, 
    reset => pl_reset,                        
    trig => dma_trig, --soft_trig, 
    reg_o => reg_o_dma, 	 
	adc_data => adc_data_dma, 
	dma_active => dma_adc_active,
    m_axis_tdata => dma_adc_tdata, 
    m_axis_tkeep => dma_adc_tkeep,
    m_axis_tlast => dma_adc_tlast, 
    m_axis_tready => dma_adc_tready, 
    m_axis_tvalid => dma_adc_tvalid   
  );    


tbttoddr: entity work.tbt2dma
  port map(
    sys_clk => pl_clk1, 
    adc_clk => adc_clk, 
    reset => pl_reset,                         
    trig => dma_trig, --soft_trig, 
    reg_o => reg_o_dma,  	 
	tbt_data => tbt_data, 
	tbt_trig => tbt_trig,
	dma_active => dma_tbt_active,
    m_axis_tdata => dma_tbt_tdata, 
    m_axis_tkeep => dma_tbt_tkeep,
    m_axis_tlast => dma_tbt_tlast, 
    m_axis_tready => dma_tbt_tready, 
    m_axis_tvalid => dma_tbt_tvalid   
  );    

fatoddr: entity work.fa2dma
  port map(
    sys_clk => pl_clk1, 
    adc_clk => adc_clk, 
    reset => pl_reset,                         
    trig => dma_trig, --soft_trig, 
    reg_o => reg_o_dma,  	 
	fa_data => fa_data, 
	fa_trig => fa_trig,
	dma_active => dma_fa_active,
    m_axis_tdata => dma_fa_tdata, 
    m_axis_tkeep => dma_fa_tkeep,
    m_axis_tlast => dma_fa_tlast, 
    m_axis_tready => dma_fa_tready, 
    m_axis_tvalid => dma_fa_tvalid   
  );    


--embedded event receiver
evr: entity work.evr_top 
  generic map (
    SIM_MODE => SIM_MODE
  )
  port map(
    sys_clk => pl_clk0,
    sys_rst => pl_reset, 
    reg_o => reg_o_evr,
    --gth_reset => gth_reset,

    gth_refclk_p => gth_evr_refclk_p,  -- 312.5 MHz reference clock
    gth_refclk_n => gth_evr_refclk_n,
    gth_tx_p => gth_evr_tx_p,
    gth_tx_n => gth_evr_tx_n,
    gth_rx_p => gth_evr_rx_p,
    gth_rx_n => gth_evr_rx_n,
      
    --trignum => evr_dma_trignum, 
    trigdly => (x"00000001"), 
    tbt_trig => evr_tbt_trig, 
    fa_trig => evr_fa_trig, 
    sa_trig => evr_sa_trig, 
    usr_trig => evr_dma_trig, 
    gps_trig => evr_gps_trig, 
    timestamp => evr_ts,  
    evr_rcvd_clk => evr_rcvd_clk
);	




ps_pl: entity work.ps_io
  port map (
    pl_clock => pl_clk0, 
    pl_reset => not pl_resetn, 
    m_axi4_m2s => m_axi4_m2s, 
    m_axi4_s2m => m_axi4_s2m, 
    fp_leds => ps_leds,
    adc_data => adc_data,
    sa_data => sa_data,
    reg_o_tbt => reg_o_tbt,
    reg_o_adc => reg_o_adc,
    reg_i_adc => reg_i_adc,
    reg_o_therm => reg_o_therm,
    reg_i_therm => reg_i_therm,    
    reg_o_adcfifo => reg_o_adcfifo, 
	reg_i_adcfifo => reg_i_adcfifo,
	reg_o_tbtfifo => reg_o_tbtfifo, 
	reg_i_tbtfifo => reg_i_tbtfifo,
	reg_o_dma => reg_o_dma,
	reg_i_dma => reg_i_dma,
	reg_o_dsa => reg_o_dsa,
	reg_o_pll => reg_o_pll,
	reg_i_pll => reg_i_pll,
	reg_o_evr => reg_o_evr, 
	reg_i_evr => reg_i_evr,
	reg_o_swrffe => reg_o_swrffe,
	ioc_access_led => ioc_access_led
          
  );




system_i: component system
  port map (
    pl_clk0 => pl_clk0,
    pl_clk1 => pl_clk1,
    pl_resetn => pl_resetn,
     
    m_axi_araddr => m_axi4_m2s.araddr, 
    m_axi_arprot => m_axi4_m2s.arprot,
    m_axi_arready => m_axi4_s2m.arready,
    m_axi_arvalid => m_axi4_m2s.arvalid,
    m_axi_awaddr => m_axi4_m2s.awaddr,
    m_axi_awprot => m_axi4_m2s.awprot,
    m_axi_awready => m_axi4_s2m.awready,
    m_axi_awvalid => m_axi4_m2s.awvalid,
    m_axi_bready => m_axi4_m2s.bready,
    m_axi_bresp => m_axi4_s2m.bresp,
    m_axi_bvalid => m_axi4_s2m.bvalid,
    m_axi_rdata => m_axi4_s2m.rdata,
    m_axi_rready => m_axi4_m2s.rready,
    m_axi_rresp => m_axi4_s2m.rresp,
    m_axi_rvalid => m_axi4_s2m.rvalid,
    m_axi_wdata => m_axi4_m2s.wdata,
    m_axi_wready => m_axi4_s2m.wready,
    m_axi_wstrb => m_axi4_m2s.wstrb,
    m_axi_wvalid => m_axi4_m2s.wvalid,
    
    s_axis_s2mm_adc_tdata => dma_adc_tdata,
    s_axis_s2mm_adc_tkeep => dma_adc_tkeep,
    s_axis_s2mm_adc_tlast => dma_adc_tlast, 
    s_axis_s2mm_adc_tready => dma_adc_tready,
    s_axis_s2mm_adc_tvalid => dma_adc_tvalid,
    s_axis_s2mm_tbt_tdata => dma_tbt_tdata,
    s_axis_s2mm_tbt_tkeep => dma_tbt_tkeep,
    s_axis_s2mm_tbt_tlast => dma_tbt_tlast, 
    s_axis_s2mm_tbt_tready => dma_tbt_tready,
    s_axis_s2mm_tbt_tvalid => dma_tbt_tvalid,
    s_axis_s2mm_fa_tdata => dma_fa_tdata,
    s_axis_s2mm_fa_tkeep => dma_fa_tkeep,
    s_axis_s2mm_fa_tlast => dma_fa_tlast, 
    s_axis_s2mm_fa_tready => dma_fa_tready,
    s_axis_s2mm_fa_tvalid => dma_fa_tvalid     
    );




--stretch the sa_trig signal so can be seen on LED
sa_led : entity work.stretch
  port map (
	clk => adc_clk,
	reset => pl_reset, 
	sig_in => sa_trig, 
	len => 3000000, -- ~25ms;
	sig_out => sa_trig_stretch
);	  	

--stretch the sa_trig signal so can be seen on LED
pscmsg_led : entity work.stretch
  port map (
	clk => pl_clk0,
	reset => pl_reset, 
	sig_in => ps_leds(0), 
	len => 3000000, -- ~25ms;
	sig_out => ps_fpled_stretch
);	  	



end behv;
