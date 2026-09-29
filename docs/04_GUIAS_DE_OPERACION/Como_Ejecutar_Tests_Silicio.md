# Guía de Operación: Cómo Ejecutar los Tests de Alice en Silicio

> **Plataforma**: Digilent Nexys Video (Xilinx Artix-7 `XC7A200T-1SBG484C`)  
> **Conectores físicos**: Puerto micro-USB PROG/UART (JTAG + Puerto Serie FT2232H/FT232R)  
> **Script de automatización**: `verify_alice_key.py`  

---

## 🔌 1. Conexiones Físicas

1. Conectar la placa **Nexys Video** al PC mediante el cable micro-USB en el conector **PROG / UART**.
2. Conectar la fuente de alimentación de 12V de la placa y encender el interruptor de encendido (LED rojo `POWER` encendido).
3. Verificar en Linux que el dispositivo USB está reconocido:
   ```bash
   lsusb | grep -i future
   # Debe aparecer: Future Technology Devices International, Ltd FT2232H Dual UART/FIFO IC
   ```
4. Comprobar los puertos serie asignados:
   ```bash
   ls -la /dev/ttyUSB*
   # Habitualmente /dev/ttyUSB0 o /dev/ttyUSB2
   ```

---

## 🚀 2. Ejecutar el Banco de Pruebas Automatizado

El script `verify_alice_key.py` automatiza:
- Detección automática del puerto serie FTDI.
- Apertura del canal serie a 9600 baudios.
- Conexión vía **Xilinx Software Debugger (XSDB)** por JTAG.
- Carga y programación del bitstream `design_1_wrapper.bit` en la FPGA.
- Descarga y ejecución del archivo ELF `cvqkd_alice_application.elf` en el procesador MicroBlaze.
- Captura de telemetría UART y comparación de la clave extraída bit a bit contra Bob.

### Comando de ejecución:
```bash
cd /home/drg/TFG/cvqkd_code
sudo ./verify_alice_key.py
```

*(Se requiere `sudo` para que `xsdb` tenga acceso a los dispositivos JTAG `/dev/bus/usb` sin errores de permisos).*

---

## ⚙️ 3. Opciones Configurables en `verify_alice_key.py`

En la cabecera de `verify_alice_key.py`:

```python
BITSTREAM_PATH = "/home/drg/VivadoProyects/cvqkd_alice/cvqkd_alice.runs/impl_1/design_1_wrapper.bit"
ELF_PATH       = "/home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_application/build/cvqkd_alice_application.elf"
GOLDEN_KEY     = "/home/drg/TFG/cvqkd_code/cvqkd_matlab/data/block_bits.txt"
```

Si la FPGA ya está programada con el bitstream y solo se ha recompilado el firmware `main.c`, se puede llamar con:
```python
read_from_serial(program_bit=False)
```
Esto ahorrará los 3-4 segundos de reprogramación JTAG y simplemente reiniciará el MicroBlaze.
