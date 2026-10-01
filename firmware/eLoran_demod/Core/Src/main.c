/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Main program body
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2026 STMicroelectronics.
  * All rights reserved.
  *
  * This software is licensed under terms that can be found in the LICENSE file
  * in the root directory of this software component.
  * If no LICENSE file comes with this software, it is provided AS-IS.
  *
  ******************************************************************************
  */
/* USER CODE END Header */
/* Includes ------------------------------------------------------------------*/
#include "main.h"
#include "spi.h"
#include "tim.h"
#include "usart.h"
#include "gpio.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include "proto.h"
#include "frame.h"
#include "corr.h"
#include "demod.h"
#include <string.h>

// FPGA 추가
#include "spi.h"
#include "fpga_spi.h"
#define USE_FPGA 1        // 1=FPGA 오프로딩, 0=MCU 단독 (비교용)

/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */
//#define DIAG_BUFFER_CHECK   1		// 진단 코드: ON(1) / OFF(0)

/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

/* USER CODE BEGIN PV */
static uint8_t     g_rx_byte;                     // UART 1바이트 수신 버퍼
static int64_t     g_corr[N_PULSE][N_CAND];       // 상관값 6x3
static DemodResult g_result;
static uint8_t     g_payload[PROTO_LEN_RESULT];   // 결과 31 B
/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
/* USER CODE BEGIN PFP */
static uint32_t us_now(void);
static void     put_u32(uint8_t *p, uint32_t v);
static void     run_demod(void);
/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

// TIM2 : Prescaler 83 -> 1 tick = 1 us, Period 0xFFFFFFFF (32비트)
// uint32 뺄셈이므로 카운터가 한 바퀴 돌아도 경과시간은 정상적으로 나온다.
static uint32_t us_now(void)
{
    return __HAL_TIM_GET_COUNTER(&htim2);
}

// uint32를 리틀 엔디안 4바이트로 쓴다
static void put_u32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v      );
    p[1] = (uint8_t)(v >>  8);
    p[2] = (uint8_t)(v >> 16);
    p[3] = (uint8_t)(v >> 24);
}

// CMD_DEMOD 를 받았을 때 실행되는 본체
static void run_demod(void)
{

	// 1. FPGA 상관 계산 + SPI 전송 시간
    uint8_t status = STATUS_OK;
    uint32_t t0 = us_now();

#if USE_FPGA
    if (FPGA_ReadCorr(g_corr) != 0) status = STATUS_NO_SIGNAL;   // START->DONE->SPI
#else
    status = FRAME_SignalReady() ? STATUS_OK : STATUS_NO_SIGNAL;
    CORR_Compute(FRAME_Signal(), g_corr);
#endif
    uint32_t t1 = us_now();

// 기존 (MCU 단독)
//    uint8_t status = FRAME_SignalReady() ? STATUS_OK : STATUS_NO_SIGNAL;
//
//    uint32_t t0 = us_now();
//
//    // 1. 상관 : 6펄스 x 3후보 = 18회
//    CORR_Compute(FRAME_Signal(), g_corr);
//    uint32_t t1 = us_now();

    // 2. 판정 : Step 1 -> CDC -> MDD
    DEMOD_Run(g_corr, &g_result);
    uint32_t t2 = us_now();

    // 3. 결과 페이로드 31 B 조립
    memset(g_payload, 0, sizeof(g_payload));

    memcpy(&g_payload[RES_OFF_EST_PULSES], g_result.est_pulses, N_PULSE);
    memcpy(&g_payload[RES_OFF_BITS],       g_result.bits,       N_BITS);

    g_payload[RES_OFF_STATE]  = g_result.state;
    g_payload[RES_OFF_STATUS] = status;

    put_u32(&g_payload[RES_OFF_T_CORR],   t1 - t0);
    put_u32(&g_payload[RES_OFF_T_DECIDE], t2 - t1);
    put_u32(&g_payload[RES_OFF_T_TOTAL],  t2 - t0);

//#if DIAG_BUFFER_CHECK
//    // 하위 8비트씩: timeout / crc_err / uart_err
//    const FrameStat *st = FRAME_Stats();
//    put_u32(&g_payload[RES_OFF_T_COMM],
//            ((st->n_uart_err & 0xFF) << 16) |
//            ((st->n_crc_err  & 0xFF) <<  8) |
//             (st->n_timeout  & 0xFF));
//#else
    put_u32(&g_payload[RES_OFF_T_COMM], 0);   // FPGA 연동 전이므로 0
//#endif

    FRAME_SendResult(g_payload);

    HAL_GPIO_TogglePin(LD2_GPIO_Port, LD2_Pin);   // 동작 확인용
}

/* USER CODE END 0 */

/**
  * @brief  The application entry point.
  * @retval int
  */
int main(void)
{

  /* USER CODE BEGIN 1 */

  /* USER CODE END 1 */

  /* MCU Configuration--------------------------------------------------------*/

  /* Reset of all peripherals, Initializes the Flash interface and the Systick. */
  HAL_Init();

  /* USER CODE BEGIN Init */

  /* USER CODE END Init */

  /* Configure the system clock */
  SystemClock_Config();

  /* USER CODE BEGIN SysInit */

  /* USER CODE END SysInit */

  /* Initialize all configured peripherals */

  MX_TIM2_Init();
  MX_USART2_UART_Init();
  MX_SPI2_Init();
  MX_GPIO_Init();
  /* USER CODE BEGIN 2 */

  HAL_TIM_Base_Start(&htim2);      // 처리시간 측정용 프리러닝 카운터

  DEMOD_Init();                    // 729-entry 해시 테이블 생성
  FRAME_Init();

  HAL_UART_Receive_IT(&huart2, &g_rx_byte, 1);   // 첫 바이트 대기

  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */

  while (1)
  {
    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */

	FRAME_Tick();                  // 프레임 도중 끊기면 파서 리셋

	switch (FRAME_TakeEvent()) {

	case FRAME_LOAD:
        // 확정된 신호를 처리 버퍼로 옮긴다.
        FRAME_CommitSignal();
		break;

	case FRAME_DEMOD:
        // LOAD와 DEMOD가 연달아 도착해 LOAD 이벤트를 놓쳤을 수도 있으니
        // CommitSignal은 여러번 불러도 안전하므로 여기서 한번 더 부른다.
        FRAME_CommitSignal();
        run_demod();
		break;

	default:
		break;
	}

  }

  /* USER CODE END 3 */
}

/**
  * @brief System Clock Configuration
  * @retval None
  */
void SystemClock_Config(void)
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

  /** Configure the main internal regulator output voltage
  */
  __HAL_RCC_PWR_CLK_ENABLE();
  __HAL_PWR_VOLTAGESCALING_CONFIG(PWR_REGULATOR_VOLTAGE_SCALE2);

  /** Initializes the RCC Oscillators according to the specified parameters
  * in the RCC_OscInitTypeDef structure.
  */
  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSE;
  RCC_OscInitStruct.HSEState = RCC_HSE_BYPASS;
  RCC_OscInitStruct.PLL.PLLState = RCC_PLL_ON;
  RCC_OscInitStruct.PLL.PLLSource = RCC_PLLSOURCE_HSE;
  RCC_OscInitStruct.PLL.PLLM = 4;
  RCC_OscInitStruct.PLL.PLLN = 84;
  RCC_OscInitStruct.PLL.PLLP = RCC_PLLP_DIV2;
  RCC_OscInitStruct.PLL.PLLQ = 4;
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK)
  {
    Error_Handler();
  }

  /** Initializes the CPU, AHB and APB buses clocks
  */
  RCC_ClkInitStruct.ClockType = RCC_CLOCKTYPE_HCLK|RCC_CLOCKTYPE_SYSCLK
                              |RCC_CLOCKTYPE_PCLK1|RCC_CLOCKTYPE_PCLK2;
  RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;
  RCC_ClkInitStruct.AHBCLKDivider = RCC_SYSCLK_DIV1;
  RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV2;
  RCC_ClkInitStruct.APB2CLKDivider = RCC_HCLK_DIV1;

  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_2) != HAL_OK)
  {
    Error_Handler();
  }
}

/* USER CODE BEGIN 4 */

// 바이트가 하나 도착할 때마다 호출된다. (USART2 global interrupt)
void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance == USART2) {
        FRAME_FeedByte(g_rx_byte);
        HAL_UART_Receive_IT(huart, &g_rx_byte, 1);   // 다음 바이트 재무장
    }
}

// 오버런(ORE) 이 나면 HAL 이 수신을 중단한다.
void HAL_UART_ErrorCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance == USART2) {
        FRAME_NotifyUartError();
        HAL_UART_Receive_IT(huart, &g_rx_byte, 1);
    }
}

/* USER CODE END 4 */

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
void Error_Handler(void)
{
  /* USER CODE BEGIN Error_Handler_Debug */
  /* User can add his own implementation to report the HAL error return state */
  __disable_irq();
  while (1)
  {
  }
  /* USER CODE END Error_Handler_Debug */
}
#ifdef USE_FULL_ASSERT
/**
  * @brief  Reports the name of the source file and the source line number
  *         where the assert_param error has occurred.
  * @param  file: pointer to the source file name
  * @param  line: assert_param error line source number
  * @retval None
  */
void assert_failed(uint8_t *file, uint32_t line)
{
  /* USER CODE BEGIN 6 */
  /* User can add his own implementation to report the file name and line number,
     ex: printf("Wrong parameters value: file %s on line %d\r\n", file, line) */
  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */
