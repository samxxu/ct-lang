/* FreeRTOS glue lives in C so the CT front end never parses third-party
   headers (function-like macros are rejected by the strict C boundary). */
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "board.h"

static QueueHandle_t g_q;

static void producer(void *arg)
{
    int i;
    (void)arg;
    for (i = 1; i <= 3; i++) {
        (void)xQueueSend(g_q, &i, 0);
        vTaskDelay(1);
    }
    vTaskSuspend(0);
}

static void consumer(void *arg)
{
    int v;
    (void)arg;
    for (;;) {
        if (xQueueReceive(g_q, &v, portMAX_DELAY) == pdPASS) {
            uart_puts("q=");
            uart_putu((unsigned int)v);
            uart_puts("\n");
            if (v == 3) {
                uart_puts("done\n");
                vTaskSuspend(0);
            }
        }
    }
}

void rtos_start(void)
{
    g_q = xQueueCreate(4, sizeof(int));
    (void)xTaskCreate(producer, "p", 256, 0, 1, 0);
    (void)xTaskCreate(consumer, "c", 256, 0, 1, 0);
    vTaskStartScheduler();
}
