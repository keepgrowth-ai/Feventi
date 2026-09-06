-- 010 · corrección de 0052 · Art. 12.4 (una migración aplicada no se edita)
--
-- Las políticas de `delete` de 0052 no servían para nada: la migración 0009
-- invirtió los privilegios por defecto, así que las tablas nuevas nacen con
-- `select` para authenticated y NADA más. Sin el `grant`, Postgres ni llega a
-- evaluar la política — devuelve 42501 antes.
--
--   ERROR: 42501: permission denied for table friend_edges
--
-- Lo destapó AC-15c, que es justamente la mitad «camino feliz» de la
-- comprobación de superficie: AC-15a y AC-15b (los guardarraíles) pasaban en
-- verde. Sin el camino feliz al lado, un `revoke` de más se ve exactamente
-- igual que un `revoke` bien puesto.

grant delete on public.friend_edges to authenticated;
grant insert, delete on public.blocks to authenticated;

-- El grant es de tabla; quién puede borrar QUÉ fila lo sigue decidiendo la
-- política de 0052: solo el implicado en la arista, solo el dueño del bloqueo.
