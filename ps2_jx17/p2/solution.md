### P2 Solution

1. MTCP_BIOC_ON && MTCP_LED_SET
| Opcode        | The time it should be sent | Effect it has on the device | Returned message |
| --- |:---:|:---:|:---:|
| MTCP_BIOC_ON  | When host computer want to enable Button interrupt-on-change | Button interrupt-on-change will be generated if button is either pressed or released | MTCP_ACK |
| MTCP_LED_SET  | Set the User-set LED display values | The value will be displayed on LED display when LED display is in USR mode | MTCP_ACK |

2. MTCP_ACK && MTCP_BIOC_EVENT && MTCP_RESET
| Opcode        | The time device sends the message | Meaning of the message |
| --- |:---:|:---:|
| MTCP_ACK  | When MTC successfully completes a command | Acknowledge the host that the command is successfully received and completed |
| MTCP_BIOC_EVENT  | Button is either pressed or released and Button Interrupt-on-change mode is enabled | Button Interrupt-on-change occurs |
| MTCP_RESET | When the device re-initializes itself after a power-up, a RESET button press, or an MTCP_RESEt_DEV command | Inform the host that the device has been reset |

3. The function is inside an interrupt handler, so it must not take up too much time such as sleep.
