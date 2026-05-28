# Modelo MATLAB CV-QKD — Golden Model y Verificación

## Estructura del Repositorio

```
cvqkd_matlab/
├── lib/                          # Funciones reutilizables
│   ├── channel/                  # Simulación de canal de fibra
│   │   ├── generate_phase_noise.m
│   │   └── apply_channel_model.m
│   ├── dsp/                      # Procesado digital (Bob)
│   │   ├── recover_phase_pilots.m
│   │   ├── compensate_phase.m
│   │   ├── estimate_parameters_float.m
│   │   └── estimate_parameters_fixed.m
│   ├── ldpc/                     # Decodificación LDPC
│   │   ├── build_ldpc_matrix.m
│   │   └── ldpc_decode_scaled_minsum.m
│   ├── mdr/                      # Reconciliación 8D
│   │   └── compute_mdr_8d.m
│   ├── export/                   # Generación de ficheros .txt para RTL
│   │   └── export_vivado_testbenches.m
│   ├── utils/                    # Utilidades
│   │   ├── quantize_to_int16.m
│   │   ├── quantize_llr_to_8bit.m
│   │   └── write_binary_file.m
│   └── get_default_config.m      # Configuración centralizada
│
├── scripts/                      # Scripts principales
│   ├── main_cv_qkd_simulation.m  # Orquestador principal (modular)
│   ├── tb_generador_master.m     # Script monolítico (DEPRECATED)
│   ├── rtl_matching_ldpc_sim.m   # Verificación RTL
│   ├── compare_matlab_rtl.m      # Comparación MATLAB vs RTL
│   └── compare_rmem.m            # Comparación R_mem
│
├── data/                         # Vectores de test generados
│   ├── u_bits.txt                # LLRs iniciales (8-bit SM)
│   ├── expected_syndrome.txt     # Síndrome target
│   ├── expected_p_mem.txt        # Valores VNU por iteración
│   ├── expected_r_mem.txt        # Mensajes CNU por iteración
│   ├── bob_key_ref.txt           # Clave de referencia
│   └── BG1.txt                   # Matriz base 5G LDPC
│
└── reports/                      # Informes de verificación
    ├── comparison_report_*.txt
    ├── comparison_report_*.html
    └── ber_convergence_*.png
```

## Inicio Rápido

```matlab
>> cd cvqkd_matlab/scripts

% Verificar todos los módulos (30 seg)
>> test_modular_code

% Ejecutar simulación completa (2-5 min)
>> main_cv_qkd_simulation
```

## Configuración

Todos los parámetros en un solo lugar:

```matlab
>> cfg = get_default_config();
>> cfg.physical.V_A_snu = 10.0;       % Varianza de Alice
>> cfg.ldpc.max_iter = 100;           % Iteraciones LDPC
>> cfg.ldpc.alpha = 0.75;             % Factor de atenuación Min-Sum
>> main_cv_qkd_simulation             % Ejecutar con nueva config
```

## Comparación MATLAB vs RTL

```matlab
>> results = compare_matlab_rtl('html', true);         % Comparar
>> results = compare_matlab_rtl('regenerate', true);   % Regenerar datos + comparar
>> results = compare_matlab_rtl('verbose', true);      % Modo detallado
```

### Criterios PASS

- Ambos modelos convergen (diferencia ≤ 2 iteraciones)
- BER final = 0.000000
- Síndrome correcto en todas las filas

### Salida esperada

```
Overall Result: [PASS]
MATLAB Convergence: 9 iterations
RTL Convergence: 9 iterations
MATLAB Final BER: 0.000000
RTL Final BER: 0.000000
```

## Archivos Generados

Los scripts generan ficheros en `data/` que consumen los testbenches RTL:

| Archivo | Formato | Descripción |
|---------|---------|-------------|
| `u_bits.txt` | Binario (8-bit SM) | LLRs iniciales del canal |
| `bob_key_ref.txt` | Binario | Clave original de Bob (68×384) |
| `expected_syndrome.txt` | Binario | Síndrome target (46×384) |
| `expected_p_mem.txt` | Hex (16-bit SM) | Valores VNU por iteración |
| `expected_r_mem.txt` | Hex (16-bit SM) | Mensajes CNU por iteración |

## Documentación Relacionada

| Documento | Descripción |
|-----------|-------------|
| `../README.md` | Visión general del proyecto CV-QKD |
| `../LDPC_DECODER.md` | Arquitectura detallada del decodificador LDPC |
