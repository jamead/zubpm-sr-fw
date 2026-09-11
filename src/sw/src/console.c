/********************************************************************
*  Menu Thread
*
*  This thread is responsible for all console menu related items
********************************************************************/

#include <stdio.h>
#include <string.h>
#include <sleep.h>
#include "xiicps.h"
#include "xuartps_hw.h"
#include "pm_api_sys.h"
#include "pm_defs.h"


#include "lwip/sockets.h"
#include "netif/xadapter.h"
#include "lwipopts.h"
#include "xil_printf.h"
#include "FreeRTOS.h"
#include "task.h"

/* Hardware support includes */
#include "pl_regs.h"
#include "local.h"
#include "zubpm.h"

#define MAX_INPUT_LEN      64

//typedef struct {
//  u8 ipaddr[4];
//  u8 ipmask[4];
//  u8 ipgw[4];
//} ip_t;




typedef struct {
  char entryCh;
  char *entryStr;
  void (* entryFunc)(void);
} menu_entry_t;



void exec_menu(const char *head, const menu_entry_t *m, size_t m_len);
void test_menu(void);




void menu_get_ipaddr(u8 *octets)
{
    char c; //ip_address[16];
    char ip_addr[40];
    u32 index=0;


    //xil_printf("Enter an IP address (format: x.x.x.x): ");
    while (1) {
       c = inbyte();
       xil_printf("%c",c);
       if (c == '\b')
    	   index--;
       else if (c == '\r')  {
    	   xil_printf("\r");
    	   ip_addr[index++] = '\n';
    	   break;
       }
       else
         ip_addr[index++] = c;
    }

    // TODO check if IP address is valid
    //xil_printf("\r\nStored IP Address: %s\r\n", ip_addr);
    //check if valid format
    sscanf(ip_addr, "%hhu.%hhu.%hhu.%hhu", &octets[0], &octets[1], &octets[2], &octets[3]);

}


u8 get_binary_input(void) {
    char c;

    c = inbyte();
    xil_printf("%c",c);
    if (c == '0') {
        return 0;
    } else if (c == '1') {
        return 1;
    } else {
       printf("\r\nInvalid input. Please enter 0 or 1.\r\n");
       return -1;
    }

}



void dump_eeprom(void)
{
  xil_printf("Reading EEPROM...\r\n");
  eeprom_dump();
}




// Read a line (blocking) from UART into buffer
void uart_read_line(char *buffer, int max_len) {
    int idx = 0;
    char c;

    while (idx < max_len - 1) {
        // Wait for data from UART
        while (!XUartPs_IsReceiveData(XPAR_XUARTPS_0_BASEADDR)) {
            vTaskDelay(pdMS_TO_TICKS(1)); // Yield to other tasks
        }

        c = XUartPs_ReadReg(XPAR_XUARTPS_0_BASEADDR, XUARTPS_FIFO_OFFSET) & 0xFF;

        // Echo the character back if needed
        XUartPs_SendByte(XPAR_XUARTPS_0_BASEADDR, c);

        if (c == '\r' || c == '\n') {
            break;  // End of line
        }

        buffer[idx++] = c;
    }

    buffer[idx] = '\0';  // Null-terminate

    // Optionally send newline
    xil_printf("\r\n");
}


void machine_sel(void)
{
  u8 val;

  xil_printf("\r\nzuBPM Location: 0 = SR,  1 = Booster\r\n");
  if ((val = get_binary_input()) != (u8)-1) {
     i2c_eeprom_writeBytes(0x20, &val, 1);
     if (val == 0) {
    	xil_printf("Setting to SR\r\n");
        Xil_Out32(XPAR_M_AXI_BASEADDR + MACH_SEL_REG, 0);
     }
     else {
     	xil_printf("Setting to Booster\r\n");
        Xil_Out32(XPAR_M_AXI_BASEADDR + MACH_SEL_REG, 1);
     }
  }
}


void set_kx_ky_console(void)
{
    char buffer[MAX_INPUT_LEN];
    char *endptr;

    float kx_mm;
    float ky_mm;

    u32 kx_nm;
    u32 ky_nm;

    xil_printf("\r\nEnter Kx in mm: ");
    uart_read_line(buffer, MAX_INPUT_LEN);

    kx_mm = strtof(buffer, &endptr);

    if (endptr == buffer || *endptr != '\0') {
        printf("Invalid Kx value\r\n");
        return;
    }

    xil_printf("\r\nEnter Ky in mm: ");
    uart_read_line(buffer, MAX_INPUT_LEN);

    ky_mm = strtof(buffer, &endptr);

    if (endptr == buffer || *endptr != '\0') {
        printf("Invalid Ky value\r\n");
        return;
    }

    /* Convert mm -> nm */
    kx_nm = (u32)(kx_mm * 1000000.0f + 0.5f);
    ky_nm = (u32)(ky_mm * 1000000.0f + 0.5f);

    /* Program FPGA */
    set_kxky(HOR, kx_nm);
    set_kxky(VERT, ky_nm);

    /* Save persistent copy */
    save_kxky_eeprom(kx_nm, ky_nm);

    printf("\r\nKx = %.4f mm = %lu nm\r\n",
           kx_mm, (unsigned long)kx_nm);

    printf("Ky = %.4f mm = %lu nm\r\n",
           ky_mm, (unsigned long)ky_nm);
}


void display_all_settings(void)
{
    u32 machine_sel;
    u32 kx_nm;
    u32 ky_nm;

    machine_sel = Xil_In32(XPAR_M_AXI_BASEADDR + MACH_SEL_REG);
    kx_nm       = Xil_In32(XPAR_M_AXI_BASEADDR + KX_REG);
    ky_nm       = Xil_In32(XPAR_M_AXI_BASEADDR + KY_REG);

    xil_printf("\r\n");
    xil_printf("========================================\r\n");
    xil_printf("            zuBPM Settings\r\n");
    xil_printf("========================================\r\n");

    /* Machine selection */
    if (machine_sel == 0) {
        xil_printf("Machine Select   : Storage Ring\r\n");
    }
    else if (machine_sel == 1) {
        xil_printf("Machine Select   : Booster\r\n");
    }
    else {
        xil_printf("Machine Select   : Invalid (%lu)\r\n",
                   (unsigned long)machine_sel);
    }

    /* IP address */
    if (server_netif.ip_addr.addr == 0) {
        xil_printf("IP Address       : Not assigned\r\n");
    }
    else {
        xil_printf("IP Address       : %s\r\n",
                   inet_ntoa(server_netif.ip_addr.addr));
    }

    /* IOC access count */
    xil_printf("IOC Access Count : %lu\r\n",
               (unsigned long)get_ioc_access_count());

    /*
     * Kx/Ky are stored in the FPGA in nm.
     * Use printf here because we want floating-point mm display.
     */
    printf("Kx               : %.4f mm (%lu nm)\r\n",
           (float)kx_nm / 1000000.0f,
           (unsigned long)kx_nm);

    printf("Ky               : %.4f mm (%lu nm)\r\n",
           (float)ky_nm / 1000000.0f,
           (unsigned long)ky_nm);

    xil_printf("========================================\r\n\r\n");
}





void print_ip_address(void)
{
    if (server_netif.ip_addr.addr == 0) {
        xil_printf("Assigned IP Address: not assigned\r\n");
    } else {
        xil_printf("Assigned IP Address: %s\r\n",
                   inet_ntoa(server_netif.ip_addr.addr));
    }
}


void print_ioc_access_count(void)
{
    printf("IOC access count: %lu\r\n",
           (unsigned long)get_ioc_access_count());
}




void exec_menu(const char *head, const menu_entry_t *m, size_t m_len)
{
  const char *defaultHead = "Select:";
  size_t i;
  char choice;
  int exit_flag = 0;

  if (head == NULL)
  {
    head = defaultHead;
  }

  while (!exit_flag)
  {
	//play nice, don't use all the cpu resources.
	vTaskDelay(pdMS_TO_TICKS(100));

    printf("\r\n%s\r\n", head);
    for (i = 0; i < m_len; i++)
    {
      printf("  %c:  %s\r\n", m[i].entryCh, m[i].entryStr);
    }
    printf("  Q:  quit\r\n");


    while (!XUartPs_IsReceiveData(XPAR_XUARTPS_0_BASEADDR)) {
        vTaskDelay(pdMS_TO_TICKS(10)); // Yield to other tasks
    }
    choice = XUartPs_ReadReg(XPAR_XUARTPS_0_BASEADDR, XUARTPS_FIFO_OFFSET) & 0xFF;


    if (isalpha((int)choice))
      choice = toupper((int)choice);
    printf("%c\r\n\r\n", choice);

    for (i = 0; i < m_len; i++) {
      if (m[i].entryCh == choice) {
        if (m[i].entryFunc != NULL)
          m[i].entryFunc();
        break;
      }
    }
    if (choice == 'Q')
    {
      exit_flag = 1;
    }
  }
}



static
void printTaskStats(void)
{
    TaskStatus_t taskStatusArray[MAX_TASKS];
    UBaseType_t taskCount;
    uint32_t totalRunTime;

    taskCount = uxTaskGetSystemState(taskStatusArray, MAX_TASKS, &totalRunTime);

    printf("\n%-16s %-6s %-5s %-12s %-12s %-8s\n",
           "Task", "State", "Prio", "Stack Free", "Runtime", "%%CPU");

    for (UBaseType_t i = 0; i < taskCount; i++) {
        char stateChar;
        switch (taskStatusArray[i].eCurrentState) {
            case eRunning:    stateChar = 'R'; break;
            case eReady:      stateChar = 'Y'; break;
            case eBlocked:    stateChar = 'B'; break;
            case eSuspended:  stateChar = 'S'; break;
            case eDeleted:    stateChar = 'D'; break;
            default:          stateChar = '?'; break;
        }

        float cpuPercent = totalRunTime > 0
                           ? (taskStatusArray[i].ulRunTimeCounter * 100.0f) / totalRunTime
                           : 0.0f;

        printf("%-16s %-6c %-5lu %-12lu %-12lu %6.2f%%\n",
               taskStatusArray[i].pcTaskName,
               stateChar,
               (unsigned long)taskStatusArray[i].uxCurrentPriority,
               (unsigned long) taskStatusArray[i].usStackHighWaterMark,
               (unsigned long)taskStatusArray[i].ulRunTimeCounter,
               cpuPercent);
    }
}


void reboot(void)
{
    u8 val;

    xil_printf("\r\nAre you sure you want to reboot?\r\n");
    xil_printf("Press 1 to continue, any other key to not reboot\r\n");

    val = get_binary_input();

    if (val != 1) {
        xil_printf("Reboot cancelled\r\n");
        return;
    }

    xil_printf("\r\nRebooting zuBPM...\r\n");

    vTaskDelay(pdMS_TO_TICKS(100));

    XPm_SystemShutdown(
        PMF_SHUTDOWN_TYPE_RESET,
        PMF_SHUTDOWN_SUBTYPE_SYSTEM);

    while (1);
}






void console_menu()
{

  while (1) {

    vTaskDelay(pdMS_TO_TICKS(10));

    static const menu_entry_t menu[] = {
		{'A', "Display All Settings", display_all_settings},
		{'B', "Machine Select (SR or Booster)", machine_sel},
		{'C', "Reboot", reboot},
	    {'D', "Print FreeRTOS Stats",  printTaskStats},
		{'E', "Print Assigned IP Address",  print_ip_address},
		{'F', "Print IOC Access Count", print_ioc_access_count},
		{'G', "Set Kx and Ky (mm)", set_kx_ky_console},
		{'H', "Dump EEPROM", dump_eeprom},
	};
	static const size_t menulen = sizeof(menu)/sizeof(menu_entry_t);

	xil_printf("Running zuBPM Menu (len = %ld)\r\n", menulen);

	exec_menu("zuBPM options:", menu, menulen);

	}



}


void console_setup(void)
{
    printf("INFO: Starting console daemon\n");

    sys_thread_new("console", console_menu, NULL, THREAD_STACKSIZE, DEFAULT_THREAD_PRIO-1);
}

