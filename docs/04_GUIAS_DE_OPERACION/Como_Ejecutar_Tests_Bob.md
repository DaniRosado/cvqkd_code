# Guía de Operación: Cómo Ejecutar los Tests de Bob en Silicio (PYNQ-Z2)

> **Plataforma**: PYNQ-Z2 (Xilinx Zynq `XC7Z020-1CLG400C` @ 650 MHz)  
> **Conectores físicos**: Puerto micro-USB PROG/UART (JTAG + FTDI UART a 115200 baudios)  
> **Script de automatización**: `benchmark/run_bob_streaming.py`  
> **Firmware y Aplicación**: `cvqkd_bob_app.elf`  

---

## 🔌 1. Conexiones Físicas

1. Conectar la placa **PYNQ-Z2** al PC mediante un cable micro-USB en el conector **PROG / UART**.
2. Conectar la alimentación y colocar el interruptor en **ON** (LED verde `POWER` encendido).
3. Asegurar que el jumper de arranque de la PYNQ-Z2 está en posición **JTAG**.
4. Verificar que Linux reconoce el dispositivo FTDI:
   ```bash
   ls -la /dev/serial/by-id/usb-Xilinx_TUL*
   # Habitualmente /dev/ttyUSB1
   ```

---

## 🚀 2. Ejecutar el Banco de Streaming y Seguridad Cuántica

El script `run_bob_streaming.py` automatiza:
- Detección automática del puerto serie de la PYNQ-Z2 (115200 baudios).
- Conexión vía **Xilinx System Debugger (XSDB)**.
- Programación del bitstream `design_1_wrapper.bit` en la FPGA.
- Inicialización del Processing System (`ps7_init.tcl` y `ps7_post_config`).
- Carga y ejecución del binario `cvqkd_bob_app.elf` en el Cortex-A9.
- Captura de la telemetría de 50 tramas en tiempo real con inyección y aborto de ataques.

### Comando de ejecución:
```bash
cd /home/drg/TFG/cvqkd_code
sudo ./benchmark/run_bob_streaming.py
```

---

## 🛠️ 3. Recompilación del Firmware de Bob (`main.c` + `cvqkd_security.c`)

Si se modifican parámetros del protocolo cuántico, umbrales de Holevo o el flujo de DMA:

```bash
cd /home/drg/VitisProyects/cvqkd_bob/cvqkd_bob_app
make
```

Esto generará el nuevo binario en `build/cvqkd_bob_app.elf` en menos de 1 segundo.
