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


#include "lwip/sockets.h"
#include "netif/xadapter.h"
#include "lwipopts.h"
#include "xil_printf.h"
#include "FreeRTOS.h"
#include "task.h"

/* Hardware support includes */
#include "pl_regs.h"
#include "local.h"

#define MAX_INPUT_LEN      64

typedef struct {
  u8 ipaddr[4];
  u8 ipmask[4];
  u8 ipgw[4];
} ip_t;




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


void test_machine_eeprom(void)
{
    u8 wr = 0x5A;
    u8 rd = 0xA5;

    xil_printf("\r\nEEPROM test at address 0x20\r\n");

    i2c_eeprom_writeBytes(0x20, &wr, 1);

    vTaskDelay(pdMS_TO_TICKS(20));

    xil_printf("Before read: 0x%02X\r\n", rd);

    i2c_eeprom_readBytes(0x20, &rd, 1);

    xil_printf("Wrote      : 0x%02X\r\n", wr);
    xil_printf("Read       : 0x%02X\r\n", rd);

    if (rd == wr)
        xil_printf("EEPROM TEST PASSED\r\n");
    else
        xil_printf("EEPROM TEST FAILED\r\n");
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


void reboot() {

	u8 val;

	xil_printf("\r\nAre you sure you want to reboot?\r\n");
	xil_printf("Press 1 to continue, any other key to not reboot\r\n");
	if ((val = get_binary_input()) == 1) {
      Xil_Out32(XPS_SYS_CTRL_BASEADDR | 0x008, 0xDF0D); // SLCR SLCR_UNLOCK
      Xil_Out32(XPS_SYS_CTRL_BASEADDR | 0x200, 0x1); // SLCR PSS_RST_CTRL[SOFT_RST]
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









void console_menu()
{

  while (1) {

    vTaskDelay(pdMS_TO_TICKS(10));

    static const menu_entry_t menu[] = {
	    {'A', "Dump EEPROM", dump_eeprom},
		{'B', "Machine Select (SR or Booster)", machine_sel},
		{'C', "Reboot", reboot},
	    {'D', "Print FreeRTOS Stats",  printTaskStats},
		{'E', "Print Assigned IP Address",  print_ip_address},
		{'F', "Print IOC Access Count", print_ioc_access_count},
		{'G', "Test EEPROM", test_machine_eeprom},
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

