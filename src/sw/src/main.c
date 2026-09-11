
#include <sleep.h>
#include "netif/xadapter.h"
//#include "platform_config.h"
#include "xil_printf.h"
#include "lwip/init.h"
#include "lwip/inet.h"
#include "FreeRTOS.h"


#include "xparameters.h"
#include "xsysmonpsu.h"
#include "xiicps.h"


#include "xstatus.h"       // For XStatus

#include "pm_defs.h"
#include "pm_common.h"       // PM API functions
#include "pm_api_sys.h"
#include "xipipsu.h"



#include "local.h"
#include "pl_regs.h"
#include "zubpm.h"






#define PLATFORM_EMAC_BASEADDR XPAR_XEMACPS_0_BASEADDR
#define SYSMON_DEVICE_ID XPAR_XSYSMONPSU_0_DEVICE_ID

XIicPs IicPsInstance;	    // Instance of the IIC Device
XSysMonPsu SysMonInstance;  // Instance of the Sysmon Device
static XIpiPsu IpiInstance;


#define PLATFORM_ZYNQMP


psc_key* the_server;

//static sys_thread_t main_thread_handle;



//global buffers
char msgid30_buf[1024];
char msgid31_buf[1024];
char msgid32_buf[1024];

float thermistors[6];

uint32_t git_hash;

//ip_t ip_settings;



//XIicPs IicPsInstance;	    // Instance of the IIC Device
//XSysMonPsu SysMonInstance;  // Instance of the Sysmon Device


//TimerHandle_t xUptimeTimer;  // Timer handle
//u32 UptimeCounter = 0;  // Uptime counter



// Timer callback function
//void vUptimeTimerCallback(TimerHandle_t xTimer) {
//    UptimeCounter++;  // Increment uptime counter
//}

static uint32_t ioc_access_count = 0;



static XStatus init_xilpm(void)
{
    XIpiPsu_Config *IpiCfg;
    XStatus status;

    IpiCfg = XIpiPsu_LookupConfig(XPAR_XIPIPSU_0_DEVICE_ID);

    if (IpiCfg == NULL) {
        xil_printf("ERROR: IPI configuration not found\r\n");
        return XST_FAILURE;
    }

    status = XIpiPsu_CfgInitialize(&IpiInstance,
                                   IpiCfg,
                                   IpiCfg->BaseAddress);

    if (status != XST_SUCCESS) {
        xil_printf("ERROR: IPI initialization failed: %d\r\n",
                   status);
        return status;
    }

    status = XPm_InitXilpm(&IpiInstance);

    if (status != XST_SUCCESS) {
        xil_printf("ERROR: XilPM initialization failed: %d\r\n",
                   status);
        return status;
    }

    xil_printf("XilPM initialized\r\n");

    return XST_SUCCESS;
}








uint32_t get_ioc_access_count(void)
{
    return __atomic_load_n(&ioc_access_count, __ATOMIC_RELAXED);
}




void print_firmware_version()
{

  time_t epoch_time;
  struct tm *human_time;
  char timebuf[80];
  xil_printf("SR BPM firmware...\r\n");
  xil_printf("Module ID Number: %x\r\n", Xil_In32(XPAR_M_AXI_BASEADDR + MOD_ID_NUM));
  xil_printf("Module Version Number: %x\r\n", Xil_In32(XPAR_M_AXI_BASEADDR + MOD_ID_VER));
  xil_printf("Project ID Number: %x\r\n", Xil_In32(XPAR_M_AXI_BASEADDR + PROJ_ID_NUM));
  xil_printf("Project Version Number: %x\r\n", Xil_In32(XPAR_M_AXI_BASEADDR + PROJ_ID_VER));
  //compare to git commit with command: git rev-parse --short HEAD
  xil_printf("Git Checksum: %x\r\n", Xil_In32(XPAR_M_AXI_BASEADDR + GIT_SHASUM));
  epoch_time = Xil_In32(XPAR_M_AXI_BASEADDR + COMPILE_TIMESTAMP);
  human_time = localtime(&epoch_time);
  strftime(timebuf, sizeof(timebuf), "%Y-%m-%d %H:%M:%S", human_time);
  xil_printf("Project Compilation Timestamp: %s\r\n", timebuf);
}






s32 init_sysmon() {

	s32 Status;
    XSysMonPsu_Config *SysMonConfig;

	// Initialize the SYSMON driver
	SysMonConfig = XSysMonPsu_LookupConfig(SYSMON_DEVICE_ID);
	if (SysMonConfig == NULL) {
		return XST_FAILURE;
	}

	Status = XSysMonPsu_CfgInitialize(&SysMonInstance, SysMonConfig, SysMonConfig->BaseAddress);
	if (Status != XST_SUCCESS) {
		return XST_FAILURE;
	}

	// Self-Test the System Monitor/ADC device
	Status = XSysMonPsu_SelfTest(&SysMonInstance);
	if (Status != XST_SUCCESS) {
		xil_printf("SysMonPsu self-test failed.\n");
		return XST_FAILURE;
	}

    return XST_SUCCESS;
}


static void client_event(void *pvt, psc_event evt, psc_client *ckey)
{
    if(evt!=PSC_CONN)
        return;
    // send some "static" information once when a new client connects.
    struct {
        uint32_t git_hash;
        uint32_t serial;
    } msg = {
        .git_hash = htonl(git_hash),
        .serial = 0, // TODO: read from EEPROM
    };
    (void)pvt;

    psc_send_one(ckey, 0x100, sizeof(msg), &msg);
}




static void client_msg(void *pvt, psc_client *ckey, uint16_t msgid, uint32_t msglen, void *msg)
{
    (void)pvt;

	//xil_printf("In Client_Msg:  MsgID=%d   MsgLen=%d\r\n",msgid,msglen);
    // Count each IOC message/access event and blink front panel LED.
    __atomic_add_fetch(&ioc_access_count, 1, __ATOMIC_RELAXED);

    //blink front panel LED
    Xil_Out32(XPAR_M_AXI_BASEADDR + IOC_ACCESS_REG, 1);
    Xil_Out32(XPAR_M_AXI_BASEADDR + IOC_ACCESS_REG, 0);

    switch(msgid) {
        case 1: //register settings
        	reg_settings(msg);
        	break;
        case 5: //ping event
            break;
    }



}





static void on_startup(void *pvt, psc_key *key)
{
    (void)pvt;
    (void)key;
    lstats_setup();
    brdstats_setup();
    sadata_setup();
    livedata_setup();
    dmadata_setup();
    gendata_setup();
    thermistor_setup();
    console_setup();
}



static void realmain(void *arg)
{
    (void)arg;

    printf("Main thread running\n");

    {
        net_config conf = {};
        sdcard_handle(&conf);
        //InitSettingsfromQspi();
        net_setup(&conf);

    }

    //discover_setup();
    //tftp_setup();

    const psc_config conf = {
        .port = 3000,
        .start = on_startup,
        .conn = client_event,
        .recv = client_msg,
    };

    psc_run(&the_server, &conf);
    while(1) {
        fprintf(stderr, "ERROR: PSC server loop returns!\n");
        sys_msleep(1000);
    }
}




int main()
{

    u32 ts_s, ts_ns;
    float temp1, temp2;
    u32 i;
    XStatus status;

	xil_printf("zuBPM ...\r\n");
    print_firmware_version();

    status = init_xilpm();
    if (status != XST_SUCCESS) {
        xil_printf("WARNING: XilPM initialization failed\r\n");
    }


	prog_ad9510();
	xil_printf("Init I2c...\r\n");
	init_i2c();
	xil_printf("Init Sysmon...\r\n");
	init_sysmon();


    i2c_set_port_expander(I2C_PORTEXP1_ADDR,0x40);
    //voltage and current readback device on AFE
    ina226_init();
    usleep(10000);


    xil_printf("Programming Si569 VCXO via i2c\r\n");
    //read_si569();
    //sleep(1);
    prog_si569();
    sleep(1);
    //read_si569();
    //sleep(1);

    // oscillator for EVR reference clock
	xil_printf("Init lmk1e2...\r\n");
    write_lmk61e2();



    // Disable Switching
    Xil_Out32(XPAR_M_AXI_BASEADDR + SWRFFE_ENB_REG, 0);

    // Enable 101Tap DDC FP Filt
	Xil_Out32(XPAR_M_AXI_BASEADDR + DDC_LPFILT_SEL_REG, 0);



    //read AFE temperature from i2c bus
    i2c_set_port_expander(I2C_PORTEXP1_ADDR,0x40);
    temp1 = read_i2c_temp(BRDTEMP0_ADDR);
    temp2 = read_i2c_temp(BRDTEMP2_ADDR);
    printf("AFE:  = %5.3f  %5.3f  \r\n",temp1,temp2);
    sleep(1);
    i2c_set_port_expander(I2C_PORTEXP1_ADDR,0x0);


    xil_printf("Initializing ADC...\r\n");
	ltc2195_init();

	//EVR reset
	Xil_Out32(XPAR_M_AXI_BASEADDR + EVR_RST_REG, 0xFF);
	usleep(10);
	Xil_Out32(XPAR_M_AXI_BASEADDR + EVR_RST_REG, 0);
    usleep(1000);

    //Set Event to 32
    xil_printf("Setting Trigger Number to 32\r\n");
	Xil_Out32(XPAR_M_AXI_BASEADDR + EVR_DMA_TRIGNUM_REG, 32);

	//Set Trigger Source to EVR
    xil_printf("Setting Trigger Source to EVR\r\n");
    Xil_Out32(XPAR_M_AXI_BASEADDR + DMA_TRIGSRC_REG, 0l);

    //Set Event source to EVR
   	xil_printf("Setting Event Source to EXT\r\n");
   	Xil_Out32(XPAR_M_AXI_BASEADDR + EVENT_SRC_SEL_REG, 1);

    //read Timestamp
    //for (i=0;i<5;i++) {
    //   ts_s = Xil_In32(XPAR_M_AXI_BASEADDR + EVR_TS_S_REG);
    //   ts_ns = Xil_In32(XPAR_M_AXI_BASEADDR + EVR_TS_NS_REG);
    //   xil_printf("ts= %d    %d\r\n",ts_s,ts_ns);
    //   sleep(1);
    //}

    // Initialize DMA lengths to initial values
	Xil_Out32(XPAR_M_AXI_BASEADDR + DMA_ADCBURSTLEN_REG, 10000);
	Xil_Out32(XPAR_M_AXI_BASEADDR + DMA_TBTBURSTLEN_REG, 10000);
	Xil_Out32(XPAR_M_AXI_BASEADDR + DMA_FABURSTLEN_REG, 1000);

	//Get settings from EEPROM and program PL
	ReadEEPROMHardwareSettings();



    // TODO:  This doesn't work
    //xil_printf("System is about to reset...\n");
    // Perform the system reset
    //XPm_ResetAssert(XILPM_RESET_SOFT,XILPM_RESET_ACTION_PULSE);


    sys_thread_new("main", realmain, NULL, THREAD_STACKSIZE, DEFAULT_THREAD_PRIO);


	vTaskStartScheduler();

    //never reached
	return 0;
}
