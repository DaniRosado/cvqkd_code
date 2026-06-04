// ============================================================================
// Módulo:       mdr_bob_pkg
// Proyecto:     CV-QKD Hardware Accelerator
// Descripción:  Paquete global de parámetros arquitectónicos del módulo MDR Bob
// Dependencias: (ninguna)
// ----------------------------------------------------------------------------
// Notas de Arquitectura:
// Centraliza todas las constantes para permitir escalado modificando un único archivo.
// ============================================================================

package mdr_bob_pkg;
    // Parámetros Arquitectónicos
    localparam int DIMENSIONS = 8;
    localparam int ADC_WIDTH  = 16;

    // Parámetros de Punto Fijo (DSP)
    localparam int Q_FRAC_BITS_ROM  = 24; // Formato Q24 para la raíz inversa
    localparam int Q_FRAC_BITS_OUT  = 24; // Mensajes m formateados a Q24 (Evita overflow)

    // Dimensionamiento de Tuberías
    localparam int DELAY_STAGES = 7;
endpackage
