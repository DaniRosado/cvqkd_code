function [val_int16] = quantize_to_int16(val_double)
% QUANTIZE_TO_INT16 - Quantizes double to int16 with saturation
%
% INPUTS:
%   val_double - Double-precision value or array
%
% OUTPUTS:
%   val_int16 - int16 quantized value(s)
%
% ALGORITHM:
%   Round and saturate to [-32768, 32767]

val_int16 = int16(max(-32768, min(32767, round(val_double))));

end
