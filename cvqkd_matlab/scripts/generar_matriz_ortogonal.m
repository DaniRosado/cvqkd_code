function M = generar_matriz_ortogonal(v)
    v1 = v(1); v2 = v(2); v3 = v(3); v4 = v(4);
    v5 = v(5); v6 = v(6); v7 = v(7); v8 = v(8);
    
    M = [ v1,  v2,  v3,  v4,  v5,  v6,  v7,  v8;
         -v2,  v1, -v4,  v3, -v6,  v5,  v8, -v7;
         -v3,  v4,  v1, -v2, -v7, -v8,  v5,  v6;
         -v4, -v3,  v2,  v1, -v8,  v7, -v6,  v5;
         -v5,  v6,  v7,  v8,  v1, -v2, -v3, -v4;
         -v6, -v5,  v8, -v7,  v2,  v1,  v4, -v3;
         -v7, -v8, -v5,  v6,  v3, -v4,  v1,  v2;
         -v8,  v7, -v6, -v5,  v4,  v3, -v2,  v1 ];
end
