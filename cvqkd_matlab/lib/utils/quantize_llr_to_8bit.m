function [llr_8bit, scale_factor] = quantize_llr_to_8bit(llr_float, target_scale)
% QUANTIZE_LLR_TO_8BIT - Quantizes LLRs to 8-bit sign-magnitude format
%
% INPUTS:
%   llr_float    - Floating-point LLR array
%   target_scale - Target scale (e.g., 48 for ~3-sigma in 7 bits)
%
% OUTPUTS:
%   llr_8bit     - Quantized LLRs in range [-127, 127]
%   scale_factor - Actual scale factor used
%
% ALGORITHM:
%   Scale to preserve relative confidence, saturate to ±127

std_llr = std(llr_float(:));
if std_llr > 0
    scale_factor = target_scale / std_llr;
else
    scale_factor = target_scale / (max(abs(llr_float(:))) + eps);
end

llr_scaled = llr_float * scale_factor;
llr_8bit = max(-127, min(127, round(llr_scaled)));

end
