-- cristinel ababei; Mar.3.2016; CopyLeft (CL);
-- project done using Quartus II 15.1 and tested on DE2-115;
-- 
-- code name: "digital cam implementation #4";
-- features:  
--   > normal video mode; 
--   > realtime edge detection video mode; 
-- 
-- this design basically connects a CMOS camera (OV7670 module) to
-- DE2-115 board; video frames are picked up from camera, buffered
-- on the FPGA (using embedded RAM), and displayed on the VGA monitor,
-- which is also connected to the board; clock signals generated
-- inside FPGA using ALTPLL's that take as input the board's 50MHz signal
-- from on-board oscillator; 
-- we have implemented a B&W filter as well as and edge detection algorithm,
-- which are used as a two phase technique to do edge detection dynamically;
--  
-- see detailed description of the "digital camera project" at:
-- http://dejazzer.com/coen4790/DIGITAL_CAMERA/digital_camera.html
-- Credits (these are some projects from where I might have adapted code,
-- thank you!):
-- http://hamsterworks.co.nz/mediawiki/index.php/OV7670_camera <--- ov7670-fpga-vga pipeline
-- http://whoyouvotefor.info/altera_sdram.shtml <--- sdram verilog project for de2 board
-- https://code.google.com/p/vhdl-project <--- sobel filter for edge detection
-- 

 
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


entity digital_cam_impl4 is
  Port ( 
    clk_50 : in STD_LOGIC;
    btn_RESET: in STD_LOGIC; -- KEY0; manual reset;
    slide_sw_resend_reg_values : in STD_LOGIC; -- rewrite all OV7670's registers;
    slide_sw_NORMAL_OR_EDGEDETECT : in STD_LOGIC; -- 0 normal, 1 edge detection; 
    
    vga_hsync : out STD_LOGIC;
    vga_vsync : out STD_LOGIC;
    vga_r     : out STD_LOGIC_vector(7 downto 0);
    vga_g     : out STD_LOGIC_vector(7 downto 0);
    vga_b     : out STD_LOGIC_vector(7 downto 0);
    vga_blank_N : out STD_LOGIC;
    vga_sync_N  : out STD_LOGIC;
    vga_CLK     : out STD_LOGIC;
    
    ov7670_pclk  : in STD_LOGIC;
    ov7670_xclk  : out STD_LOGIC;
    ov7670_vsync : in STD_LOGIC;
    ov7670_href  : in STD_LOGIC;
    ov7670_data  : in STD_LOGIC_vector(7 downto 0);
    ov7670_sioc  : out STD_LOGIC;
    ov7670_siod  : inout STD_LOGIC;
    ov7670_pwdn  : out STD_LOGIC;
    ov7670_reset : out STD_LOGIC;

    LED_config_finished : out STD_LOGIC; -- lets us know camera registers are now written;
    LED_dll_locked : out STD_LOGIC; -- PLL is locked now;   
    LED_done : out STD_LOGIC 
  );
end digital_cam_impl4;


architecture my_structural of digital_cam_impl4 is


  COMPONENT do_edge_detection 
  Port ( 
    rst_i : in  STD_LOGIC;
    clk_i : in  STD_LOGIC; -- 25 MHz
    enable_sobel_filter : in  STD_LOGIC;
    led_sobel_done : out  STD_LOGIC; 
    rdaddr_buf1 : OUT STD_LOGIC_VECTOR (16 downto 0);
    din_buf1 : IN std_logic_vector(11 downto 0);
    wraddr_buf2 : OUT STD_LOGIC_VECTOR (16 downto 0);
    dout_buf2 : OUT std_logic_vector(11 downto 0);
    we_buf2 : OUT std_logic
  );
  end COMPONENT;

  COMPONENT do_black_white
  Port ( 
    rst_i : in  STD_LOGIC;
    clk_i : in  STD_LOGIC; -- 25 MHz
    enable_filter : in  STD_LOGIC;
    led_done : out  STD_LOGIC;
    rdaddr_buf1 : OUT STD_LOGIC_VECTOR (16 downto 0);
    din_buf1 : IN std_logic_vector(11 downto 0);
    wraddr_buf1 : OUT STD_LOGIC_VECTOR (16 downto 0);
    dout_buf1 : OUT std_logic_vector(11 downto 0);
    we_buf1 : OUT std_logic
  );
  end COMPONENT;

  COMPONENT VGA
  PORT(
    CLK25 : IN std_logic;    
    Hsync : OUT std_logic;
    Vsync : OUT std_logic;
    Nblank : OUT std_logic;      
    clkout : OUT std_logic;
    activeArea : OUT std_logic;
    Nsync : OUT std_logic
    );
  END COMPONENT;

  COMPONENT ov7670_controller
  PORT(
    clk : IN std_logic;
    resend : IN std_logic;    
    siod : INOUT std_logic;      
    config_finished : OUT std_logic;
    sioc : OUT std_logic;
    reset : OUT std_logic;
    pwdn : OUT std_logic;
    xclk : OUT std_logic
    );
  END COMPONENT;

  COMPONENT frame_buffer
  PORT(
    data : IN std_logic_vector(11 downto 0);
    rdaddress : IN std_logic_vector(16 downto 0);
    rdclock : IN std_logic;
    wraddress : IN std_logic_vector(16 downto 0);
    wrclock : IN std_logic;
    wren : IN std_logic;          
    q : OUT std_logic_vector(11 downto 0)
    );
  END COMPONENT;

  COMPONENT ov7670_capture
  PORT(
    pclk : IN std_logic;
    vsync : IN std_logic;
    href : IN std_logic;
    d : IN std_logic_vector(7 downto 0);          
    addr : OUT std_logic_vector(16 downto 0);
    dout : OUT std_logic_vector(11 downto 0);
    we : OUT std_logic;
    end_of_frame : out STD_LOGIC
    );
  END COMPONENT;

  COMPONENT RGB
  PORT(
    Din : IN std_logic_vector(11 downto 0);
    Nblank : IN std_logic;          
    R : OUT std_logic_vector(7 downto 0);
    G : OUT std_logic_vector(7 downto 0);
    B : OUT std_logic_vector(7 downto 0)
    );
  END COMPONENT;

  COMPONENT Address_Generator
  PORT(
    rst_i : in std_logic;
    CLK25       : IN  std_logic;
    enable      : IN  std_logic;       
    vsync       : in  STD_LOGIC;
    address     : OUT std_logic_vector(16 downto 0)
    );
  END COMPONENT;
  
  COMPONENT debounce 
    port(
      clk, reset: in std_logic;
      sw: in std_logic;
      db: out std_logic
    );
  end COMPONENT;

  -- DE2-115 board has an Altera Cyclone V E, which has ALTPLLs;
  COMPONENT my_altpll
  PORT
  (
    areset    : IN STD_LOGIC  := '0';
    inclk0    : IN STD_LOGIC  := '0';
    c0    : OUT STD_LOGIC ;
    c1    : OUT STD_LOGIC ;
    c2    : OUT STD_LOGIC ;
    c3    : OUT STD_LOGIC ;
    locked    : OUT STD_LOGIC 
  );
  END COMPONENT;

  -- use the Altera MegaWizard to generate the ALTPLL module; generate 3 clocks, 
  -- clk0 @ 100 MHz
  -- clk1 @ 100 MHz with a phase adjustment of -3ns
  -- clk2 @ 50 MHz and 
  -- clk3 @ 25 MHz 
  signal clk_100 : std_logic;       -- clk0: 100 MHz
  signal clk_100_3ns : std_logic;   -- clk1: 100 MHz with phase adjustment of -3ns
  signal clk_50_camera : std_logic; -- clk2: 50 MHz
  signal clk_25_vga : std_logic;    -- clk3: 25 MHz
  signal dll_locked : std_logic;
  signal done_BW : std_logic := '0';
  signal done_ED : std_logic := '0';
  signal done_capture_new_frame : std_logic := '0';

  -- buffer 1;
  signal wren_buf_1 : std_logic;
  signal wraddress_buf_1 : std_logic_vector(16 downto 0); 
  signal wrdata_buf_1 : std_logic_vector(11 downto 0);
  signal rdaddress_buf_1 : std_logic_vector(16 downto 0); 
  signal rddata_buf_1 : std_logic_vector(11 downto 0);  
  -- signals generated by different entities will be multiplexed into the
  -- inputs above of buffer 1; 
  signal rdaddress_buf12_from_addr_gen : std_logic_vector(16 downto 0); -- muxed to both buf1 and buf2;
  signal rdaddress_buf1_from_do_BW : std_logic_vector(16 downto 0);
  signal rdaddress_buf1_from_do_ED : std_logic_vector(16 downto 0);
  signal wren_buf1_from_ov7670_capture : std_logic;
  signal wraddress_buf1_from_ov7670_capture : std_logic_vector(16 downto 0);
  signal wrdata_buf1_from_ov7670_capture : std_logic_vector(11 downto 0);
  signal wren_buf1_from_do_BW : std_logic; 
  signal wraddress_buf1_from_do_BW : std_logic_vector(16 downto 0);
  signal wrdata_buf1_from_do_BW : std_logic_vector(11 downto 0);  
    
  -- buffer 2;
  signal wren_buf_2 : std_logic;
  signal wraddress_buf_2 : std_logic_vector(16 downto 0);
  signal wrdata_buf_2 : std_logic_vector(11 downto 0);  
  signal rdaddress_buf_2 : std_logic_vector(16 downto 0);
  signal rddata_buf_2 : std_logic_vector(11 downto 0);
  -- signals generated by different entities will be multiplexed into the
  -- inputs above of buffer 2;
  -- signals to control buffer 2 when reading it, do edge detection, and then write back into it; 
  signal wren_buf2_from_do_ED : std_logic; 
  signal wraddress_buf2_from_do_ED : std_logic_vector(16 downto 0);
  signal wrdata_buf2_from_do_ED : std_logic_vector(11 downto 0);  
  
  -- user controls;
  signal resend_reg_values : std_logic;
  signal normal_or_edgedetect : std_logic; 
  signal reset_manual : std_logic; -- by user via KEY0 push button; 
  signal reset_automatic : std_logic; -- generated internally for 2 clock cycles;
  signal reset_global : std_logic; -- combination of previous two;
  signal reset_BW_entity : std_logic;
  signal reset_ED_entity : std_logic;
  
  signal call_black_white : STD_LOGIC;
  signal call_edge_detection : STD_LOGIC;
  signal call_black_white_synchronized : std_logic := '0';  
  signal call_edge_detection_synchronized : std_logic := '0';
 
  -- RGB related;
  signal red,green,blue : std_logic_vector(7 downto 0);
  signal activeArea : std_logic;
  signal nBlank     : std_logic;
  signal vSync      : std_logic;
  -- data_to_rgb should the multiplexing of rddata_buf_1 (when displaying
  -- video directly) or rddata_buf_2 (for realtime edge detection video mode);
  signal data_to_rgb : std_logic_vector(11 downto 0);

  -- top level control;
	type state_type is (S0_RESET, S1_RESET_BW, S2_PROCESS_BW, S3_DONE_BW, S4_RESET_ED, 
    S5_PROCESS_ED, S6_DONE_ED, S7_NORMAL_VIDEO_MODE);
	signal state_current, state_next : state_type;
  
  
begin


  -- two processes for generating the control signals at the top-level;
  -- state register; process #1
  process (clk_25_vga, reset_global)
  begin
    if (reset_global = '1') then 
      state_current <= S0_RESET;
    elsif ( clk_25_vga' event and clk_25_vga = '1' ) then 
      state_current <= state_next;
    end if;
  end process; 
  -- next state and output logic; process #2
  process (clk_25_vga, state_current, normal_or_edgedetect, done_BW, done_ED)
  begin
    state_next <= state_current;
    reset_BW_entity <= '0';
    reset_ED_entity <= '0';
    call_black_white <= '0';
    call_edge_detection <= '0';
    case state_current is    
      when S0_RESET =>
        reset_BW_entity <= '1';
        reset_ED_entity <= '1';
        if (normal_or_edgedetect = '0') then -- normal video mode;
          state_next <= S7_NORMAL_VIDEO_MODE; 
          data_to_rgb <= rddata_buf_1; -- show buf1 on VGA monitor;
          -- signals of buf1;
          wren_buf_1 <= wren_buf1_from_ov7670_capture;
          wraddress_buf_1 <= wraddress_buf1_from_ov7670_capture;
          wrdata_buf_1 <= wrdata_buf1_from_ov7670_capture;
          rdaddress_buf_1 <= rdaddress_buf12_from_addr_gen;
          -- signals of buf2;
          wren_buf_2 <= '0'; -- disabled;
          wraddress_buf_2 <= wraddress_buf2_from_do_ED; -- dont care;
          wrdata_buf_2 <= wrdata_buf2_from_do_ED; -- dont care;        
          rdaddress_buf_2 <= rdaddress_buf12_from_addr_gen;      
        else -- realtime edge detection video mode;
          state_next <= S1_RESET_BW;
          data_to_rgb <= rddata_buf_2; -- show buf2 on VGA monitor; 
          -- signals of buf1;
          wren_buf_1 <= wren_buf1_from_do_BW; 
          wraddress_buf_1 <= wraddress_buf1_from_do_BW;
          wrdata_buf_1 <= wrdata_buf1_from_do_BW;
          rdaddress_buf_1 <= rdaddress_buf1_from_do_BW;        
          -- signals of buf2;
          wren_buf_2 <= '0'; -- disabled;
          wraddress_buf_2 <= wraddress_buf2_from_do_ED; -- dont care;
          wrdata_buf_2 <= wrdata_buf2_from_do_ED; -- dont care; 
          rdaddress_buf_2 <= rdaddress_buf12_from_addr_gen;        
        end if; 
      -- next states, except the last one, are went thru only during realtime 
      -- edge detection video mode;
      when S1_RESET_BW =>                
          reset_BW_entity <= '1';
          state_next <= S2_PROCESS_BW; 
          data_to_rgb <= rddata_buf_2; -- show buf2 on VGA monitor;
          -- signals of buf1;
          wren_buf_1 <= wren_buf1_from_do_BW; 
          wraddress_buf_1 <= wraddress_buf1_from_do_BW;
          wrdata_buf_1 <= wrdata_buf1_from_do_BW;
          rdaddress_buf_1 <= rdaddress_buf1_from_do_BW;        
          -- signals of buf2;
          wren_buf_2 <= '0'; -- disabled;
          wraddress_buf_2 <= wraddress_buf2_from_do_ED; -- dont care;
          wrdata_buf_2 <= wrdata_buf2_from_do_ED; -- dont care; 
          rdaddress_buf_2 <= rdaddress_buf12_from_addr_gen;        
      when S2_PROCESS_BW =>
          call_black_white <= '1'; -- used to generate call_black_white_synchronized;
          if done_BW = '0' then
            state_next <= S2_PROCESS_BW;
          else
            state_next <= S3_DONE_BW;
          end if;
          data_to_rgb <= rddata_buf_2; -- show buf2 on VGA monitor;
          -- signals of buf1;
          wren_buf_1 <= wren_buf1_from_do_BW; 
          wraddress_buf_1 <= wraddress_buf1_from_do_BW;
          wrdata_buf_1 <= wrdata_buf1_from_do_BW;
          rdaddress_buf_1 <= rdaddress_buf1_from_do_BW;        
          -- signals of buf2;
          wren_buf_2 <= '0'; -- disabled;
          wraddress_buf_2 <= wraddress_buf2_from_do_ED; -- dont care;
          wrdata_buf_2 <= wrdata_buf2_from_do_ED; -- dont care; 
          rdaddress_buf_2 <= rdaddress_buf12_from_addr_gen;        
      when S3_DONE_BW =>
          reset_BW_entity <= '1'; -- to put it in idle immediately; done BW is thus just one cycle;
          state_next <= S4_RESET_ED;
          data_to_rgb <= rddata_buf_2; -- show buf2 on VGA monitor;
          -- signals of buf1;
          wren_buf_1 <= '0'; -- disabled;
          wraddress_buf_1 <= wraddress_buf1_from_do_BW;
          wrdata_buf_1 <= wrdata_buf1_from_do_BW;
          rdaddress_buf_1 <= rdaddress_buf1_from_do_BW;        
          -- signals of buf2;
          wren_buf_2 <= '0'; -- disabled;
          wraddress_buf_2 <= wraddress_buf2_from_do_ED; -- dont care;
          wrdata_buf_2 <= wrdata_buf2_from_do_ED; -- dont care; 
          rdaddress_buf_2 <= rdaddress_buf12_from_addr_gen;        
      when S4_RESET_ED =>
          reset_ED_entity <= '1';
          state_next <= S5_PROCESS_ED; 
          data_to_rgb <= rddata_buf_2; -- show buf2 on VGA monitor;          
          -- signals of buf1; 
          wren_buf_1 <= '0'; -- disabled;
          wraddress_buf_1 <= wraddress_buf1_from_do_BW; -- dont care;
          wrdata_buf_1 <= wrdata_buf1_from_do_BW; -- dont care;
          rdaddress_buf_1 <= rdaddress_buf1_from_do_ED; -- here we start reading from buf1;
          -- signals of buf2;
          wren_buf_2 <= wren_buf2_from_do_ED; 
          wraddress_buf_2 <= wraddress_buf2_from_do_ED;
          wrdata_buf_2 <= wrdata_buf2_from_do_ED;
          rdaddress_buf_2 <= rdaddress_buf12_from_addr_gen;
      when S5_PROCESS_ED =>
          call_edge_detection <= '1';
          if done_ED = '0' then
            state_next <= S5_PROCESS_ED;
          else
            state_next <= S6_DONE_ED;
          end if; 
          data_to_rgb <= rddata_buf_2; -- show buf2 on VGA monitor;
          -- signals of buf1; 
          wren_buf_1 <= '0'; -- disabled;
          wraddress_buf_1 <= wraddress_buf1_from_do_BW; -- dont care;
          wrdata_buf_1 <= wrdata_buf1_from_do_BW; -- dont care;
          rdaddress_buf_1 <= rdaddress_buf1_from_do_ED;
          -- signals of buf2;
          wren_buf_2 <= wren_buf2_from_do_ED; 
          wraddress_buf_2 <= wraddress_buf2_from_do_ED;
          wrdata_buf_2 <= wrdata_buf2_from_do_ED;
          rdaddress_buf_2 <= rdaddress_buf12_from_addr_gen;
      when S6_DONE_ED =>
          reset_ED_entity <= '1'; -- to put it in idle immediately; done ED is thus just one cycle;
          state_next <= S7_NORMAL_VIDEO_MODE; -- S0_RESET; 
          data_to_rgb <= rddata_buf_2; -- show buf2 on VGA monitor; 
          -- signals of buf1; 
          wren_buf_1 <= '0'; -- disabled;
          wraddress_buf_1 <= wraddress_buf1_from_do_BW; -- dont care;
          wrdata_buf_1 <= wrdata_buf1_from_do_BW; -- dont care;
          rdaddress_buf_1 <= rdaddress_buf12_from_addr_gen; 
          -- signals of buf2;
          wren_buf_2 <= '0'; -- disabled; 
          wraddress_buf_2 <= wraddress_buf2_from_do_ED;
          wrdata_buf_2 <= wrdata_buf2_from_do_ED;
          rdaddress_buf_2 <= rdaddress_buf12_from_addr_gen;
      -- at this moment, we are done with one sequence of BW+ED; so, now
      -- allow a new frame from camera module into buf1;          
      when S7_NORMAL_VIDEO_MODE =>
        if (normal_or_edgedetect = '0') then -- normal video mode;
          state_next <= S7_NORMAL_VIDEO_MODE;
          data_to_rgb <= rddata_buf_1; -- show buf1 on VGA monitor; 
          -- signals of buf1;
          wren_buf_1 <= wren_buf1_from_ov7670_capture;
          wraddress_buf_1 <= wraddress_buf1_from_ov7670_capture;
          wrdata_buf_1 <= wrdata_buf1_from_ov7670_capture;
          rdaddress_buf_1 <= rdaddress_buf12_from_addr_gen;
          -- signals of buf2;
          wren_buf_2 <= '0'; -- disabled;
          wraddress_buf_2 <= wraddress_buf2_from_do_ED; -- dont care;
          wrdata_buf_2 <= wrdata_buf2_from_do_ED; -- dont care;        
          rdaddress_buf_2 <= rdaddress_buf12_from_addr_gen;              
        else -- realtime edge detection video mode;          
          if done_capture_new_frame = '0' then 
            state_next <= S7_NORMAL_VIDEO_MODE; -- stay here till we get a complete frame from camera;
          else
            state_next <= S0_RESET;
          end if; 
          data_to_rgb <= rddata_buf_2; -- show buf2 on VGA monitor;
          -- signals of buf1;
          wren_buf_1 <= wren_buf1_from_ov7670_capture;
          wraddress_buf_1 <= wraddress_buf1_from_ov7670_capture;
          wrdata_buf_1 <= wrdata_buf1_from_ov7670_capture;
          rdaddress_buf_1 <= rdaddress_buf12_from_addr_gen;          
          -- signals of buf2;
          wren_buf_2 <= '0'; -- disabled;
          wraddress_buf_2 <= wraddress_buf2_from_do_ED; -- dont care;
          wrdata_buf_2 <= wrdata_buf2_from_do_ED; -- dont care; 
          rdaddress_buf_2 <= rdaddress_buf12_from_addr_gen;        
        end if;                
    end case;
  end process;

   
  -- LEDs; LED_config_finished is driven directly by entity ov7670_controller;
  LED_dll_locked <= reset_global; -- LEDRed[0] notifies user;
  LED_done <= (done_BW or done_ED); -- output of top-level entity;
  
  
  -- clocks generation;
  Inst_four_clocks_pll: my_altpll PORT MAP(
    areset => '0', -- reset_general?
    inclk0 => clk_50,
    c0 => clk_100,
    c1 => clk_100_3ns, -- not needed anymore;
    c2 => clk_50_camera,
    c3 => clk_25_vga,
    locked => dll_locked -- drives an LED and SDRAM controller;
  );
  
  
  -- debouncing slide switches, to get clean signals;
  Inst_debounce_resend: debounce PORT MAP(
    clk => clk_100, 
    reset => reset_global,
    sw => slide_sw_resend_reg_values,
    db => resend_reg_values
  );  
  Inst_debounce_normal_or_edgedetect: debounce PORT MAP(
    clk => clk_100, 
    reset => reset_global,
    sw => slide_sw_NORMAL_OR_EDGEDETECT,
    db => normal_or_edgedetect -- 0 is normal video video; 1 is edge detection in video mode;
  );
  -- take the inverted push button because KEY0 on DE2-115 board generates
  -- a signal 111000111; with 1 with not pressed and 0 when pressed/pushed;
  reset_manual <= not btn_RESET; -- KEY0
  -- first thing when the system is powered on, I should automatically
  -- reset everything for a few clock cycles;
  reset_automatic <= '0'; -- TODO: make it 1 for 2 clock cycles, then permanently to 0;
  reset_global <= (reset_manual or reset_automatic);
 
  
  -- video frames are buffered into buf1; from here, a frame is taken 
  -- and applied BW on it; written back into buf1; then, as second phase
  -- buf1 is read from by ED, which places result into buf2; from where
  -- it is displayed on VGA monitor; in normal video mode the above is not
  -- done; buf1 is displayed directly on VGA monitor instead;
  -- VERY IMPORTANT NOTE:  
  -- initially, in implementations 1-3, I had "wrclock => ov7670_pclk,"
  -- because the only entity to write into buf1 was camera module; here, however 
  -- BW also write its result; so, I could have either "muxed" ov7670_pclk AND clk_25_vga
  -- to feed "wrclock", or, just use directly clk_25_vga, which happens to be the same
  -- as ov7670_pclk in this particular instance;
  Inst_frame_buf_1: frame_buffer PORT MAP(
    rdaddress => rdaddress_buf_1,
    rdclock   => clk_25_vga, 
    q         => rddata_buf_1, -- goes to data_to_rgb thru mux;    
    wrclock   => clk_25_vga, -- ov7670_pclk, clock from camera module;
    wraddress => wraddress_buf_1,
    data      => wrdata_buf_1,
    wren      => wren_buf_1
  );
  -- buf2 is used to store result of ED, which read from buf1;
  Inst_frame_buf_2: frame_buffer PORT MAP(
    rdaddress => rdaddress_buf_2,
    rdclock   => clk_25_vga,
    q         => rddata_buf_2, -- goes to data_to_rgb thru mux;    
    wrclock   => clk_25_vga, 
    wraddress => wraddress_buf_2,
    data      => wrdata_buf_2,
    wren      => wren_buf_2
  );  
  

  -- camera module related blocks;
  Inst_ov7670_controller: ov7670_controller PORT MAP(
    clk             => clk_50_camera,
    resend          => resend_reg_values, -- debounced;
    config_finished => LED_config_finished, -- LEDRed[1] notifies user;
    sioc            => ov7670_sioc,
    siod            => ov7670_siod,
    reset           => ov7670_reset,
    pwdn            => ov7670_pwdn,
    xclk            => ov7670_xclk
  );
   
  Inst_ov7670_capture: ov7670_capture PORT MAP(
    pclk  => ov7670_pclk,
    vsync => ov7670_vsync,
    href  => ov7670_href,
    d     => ov7670_data,
    addr  => wraddress_buf1_from_ov7670_capture, -- wraddress_buf_1 driven by ov7670_capture;
    dout  => wrdata_buf1_from_ov7670_capture, -- wrdata_buf_1 driven by ov7670_capture;
    we    => wren_buf1_from_ov7670_capture, -- goes to mux of wren_buf_1;
    end_of_frame => done_capture_new_frame -- new out signal; did not have it before;
  );
  
  
  -- VGA related stuff;
  Inst_VGA: VGA PORT MAP(
    CLK25      => clk_25_vga,
    clkout     => vga_CLK,
    Hsync      => vga_hsync,
    Vsync      => vsync,
    Nblank     => nBlank,
    Nsync      => vga_sync_N,
    activeArea => activeArea
  );  
  Inst_RGB: RGB PORT MAP(
    Din => data_to_rgb, -- comes from either rddata_buf_1 or rddata_buf_2;
    Nblank => activeArea,
    R => red,
    G => green,
    B => blue
  );
  -- VGA related signals;
  vga_r <= red(7 downto 0);
  vga_g <= green(7 downto 0);
  vga_b <= blue(7 downto 0);
  vga_vsync <= vsync;
  vga_blank_N <= nBlank;
  
  
  -- "general purpose" address generator;
  Inst_Address_Generator: Address_Generator PORT MAP(
    rst_i => '0',
    CLK25 => clk_25_vga,
    enable => activeArea,
    vsync => vsync,
    address => rdaddress_buf12_from_addr_gen -- goes to muxes of rdaddress_buf_1 and rdaddress_buf_2;
  );
  
  
  -- generate pulse signals only when vsync is '0' to take a frame from a given buffer
  -- synchronized with the beginning of it; otherwise, pixels may be picked-up 
  -- from different frames;
  call_black_white_synchronized <= call_black_white and (not vsync);
  call_edge_detection_synchronized <= call_edge_detection and (not vsync); 
  
  -- BW entity: black_white (actually grey) filter; reads from buf1 and writes into buf1;
  Inst_black_white: do_black_white PORT MAP (
    rst_i => reset_BW_entity,
    clk_i => clk_25_vga,
    enable_filter => call_black_white_synchronized,
    led_done => done_BW,
    rdaddr_buf1 => rdaddress_buf1_from_do_BW, -- goes to mux of rdaddress_buf_1;
    din_buf1 => rddata_buf_1, -- comes from out of buf1;
    wraddr_buf1 => wraddress_buf1_from_do_BW, -- goes to mux of wraddress_buf_2;
    dout_buf1 => wrdata_buf1_from_do_BW, -- goes to mux of wrdata_buf_2;
    we_buf1 => wren_buf1_from_do_BW -- goes to mux of wren_buf_2;
  );

  -- ED entity: Sobel edge detection; reads from buf2 and writes into buf2;
  Inst_edge_detection: do_edge_detection PORT MAP (  
    rst_i => reset_ED_entity,
    clk_i => clk_25_vga, 
    enable_sobel_filter => call_edge_detection_synchronized,
    led_sobel_done => done_ED,
    rdaddr_buf1 => rdaddress_buf1_from_do_ED, -- goes to mux of rdaddress_buf_1;
    din_buf1 => rddata_buf_1, -- comes from out of buf1;
    wraddr_buf2 => wraddress_buf2_from_do_ED, -- goes to mux of wraddress_buf_2;
    dout_buf2 => wrdata_buf2_from_do_ED, -- goes to mux of wrdata_buf_2;
    we_buf2 => wren_buf2_from_do_ED -- goes to mux of wren_buf_2;
  );
  
end my_structural;
