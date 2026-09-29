# Guía de Operación: Compilación de MicroBlaze Headless vía CLI (`mb-gcc`)

> **Compilador**: `mb-gcc` (GNU Cross-Compiler para MicroBlaze, Vivado/Vitis 2025.2)  
> **Ruta del Toolchain**: `/home/drg/AMD/Xilin/2025.2/gnu/microblaze/lin/bin/mb-gcc`  
> **Proyecto Vitis**: `/home/drg/VitisProyects/cvqkd_alice/`  

---

## 🎯 Por qué Compilar por Línea de Comandos

La interfaz gráfica de Vitis 2025.2 a veces tiene dependencias de librerías compartidas con CMake/Ninja del sistema que pueden provocar fallos en entornos Linux modificados.

La compilación directa con `mb-gcc` es:
- **Instantánea** (< 1 segundo).
- **100% Determinista y reproducible**.
- **Independiente de la interfaz gráfica** de Vitis.

---

## 🛠️ Comando Maestro de Compilación y Enlazado

Ejecuta el siguiente bloque en tu terminal bash para recompilar `main.c` y regenerar el archivo `.elf`:

```bash
/home/drg/AMD/Xilin/2025.2/gnu/microblaze/lin/bin/mb-gcc -D__MICROBLAZE__ \
  -I/home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_application/src \
  -isystem /home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_platform/export/cvqkd_alice_platform/sw/standalone_microblaze_0/include \
  -ffunction-sections -fdata-sections -mxl-barrel-shift -mlittle-endian -mxl-soft-mul -mcpu=v11.0 -DSDT \
  -specs=/home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_platform/export/cvqkd_alice_platform/sw/standalone_microblaze_0/Xilinx.spec \
  -Wall -Wextra -Os -c /home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_application/src/main.c \
  -o /home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_application/build/CMakeFiles/cvqkd_alice_application.elf.dir/main.c.obj && \
/home/drg/AMD/Xilin/2025.2/gnu/microblaze/lin/bin/mb-gcc -ffunction-sections -fdata-sections \
  -mxl-barrel-shift -mlittle-endian -mxl-soft-mul -mcpu=v11.0 -DSDT \
  -specs=/home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_platform/export/cvqkd_alice_platform/sw/standalone_microblaze_0/Xilinx.spec \
  -Wl,--no-relax -Wl,--gc-sections -Wl,-T -Wl,"/home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_application/src/lscript.ld" \
  /home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_application/build/CMakeFiles/cvqkd_alice_application.elf.dir/main.c.obj \
  -L"/home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_application/src/" \
  -L"/home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_platform/export/cvqkd_alice_platform/sw/standalone_microblaze_0/lib/" \
  -Wl,--start-group,-lxilstandalone,-lxiltimer,-lgloss,-lxil,-lgcc,-lc -Wl,--end-group \
  -o /home/drg/VitisProyects/cvqkd_alice/cvqkd_alice_application/build/cvqkd_alice_application.elf && \
echo "ELF RECOMPILADO CON EXITO!"
```

---

## 🔍 Explicación de las Flags del Compilador

| Flag | Función |
| :--- | :--- |
| `-mxl-barrel-shift` | Informa a GCC de que el MicroBlaze en hardware tiene instanciado un *Barrel Shifter* hardware (desplazamientos de bits en 1 solo ciclo). |
| `-mlittle-endian` | Configura el orden de bytes en Little-Endian (estándar en MicroBlaze moderno y procesadores ARM). |
| `-mxl-soft-mul` | Configuración para multiplicador emulado o software cuando no hay multiplicador hardware dedicado en la configuración del procesador. |
| `-mcpu=v11.0` | Versión de la arquitectura del procesador MicroBlaze sintetizada en el Block Design de Vivado. |
| `-Wl,--no-relax` | Evita que el linker intente relajar las instrucciones de salto/llamada a rangos cortos, previniendo errores de reubicación en la memoria BRAM. |
| `-Wl,--gc-sections` | Elimina funciones y datos no referenciados (*Garbage Collection* de secciones), reduciendo el tamaño del binario para que quepa en la memoria local BRAM. |
| `-Wl,-T -Wl,"lscript.ld"` | Script de enlazado (*Linker Script*) que ubica el código y la pila en la memoria de MicroBlaze (`microblaze_0_local_memory`). |
