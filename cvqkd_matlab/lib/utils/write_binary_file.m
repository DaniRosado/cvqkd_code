function write_binary_file(filename, data, bits_per_entry, reverse_order)
% WRITE_BINARY_FILE - Writes binary data to text file (for $readmemb)
%
% INPUTS:
%   filename       - Output file path
%   data           - Data array (integers)
%   bits_per_entry - Bits per entry (e.g., 8, 16)
%   reverse_order  - If true, write MSB first (default: false)
%
% OUTPUT:
%   Text file with binary strings (one per line or concatenated)

if nargin < 4
    reverse_order = false;
end

fid = fopen(filename, 'w');
if fid == -1
    error('Cannot open file for writing: %s', filename);
end

for i = 1:length(data)
    val = data(i);
    if reverse_order
        % Write MSB first (for Verilog bus indexing)
        bin_str = dec2bin(mod(val, 2^bits_per_entry), bits_per_entry);
    else
        bin_str = dec2bin(mod(val, 2^bits_per_entry), bits_per_entry);
    end
    fprintf(fid, '%s\n', bin_str);
end

fclose(fid);

end
