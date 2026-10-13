-- Carritos (server/Features/Carts.luau): una estación en el hub de cada capa (shared/HubLayout). El jugador carga lo que
-- lleva, el carrito entra lleno por un túnel solo para carritos y, apenas se pierde de vista, lo que lleva se suma al
-- almacén de su base; ese carrito desaparece y sale uno vacío del túnel para el siguiente envío.
return {
	Speed = 16, -- studs por segundo
	DepositDistance = 12, -- studs dentro del túnel (pasada la reja) donde se entrega y desaparece el carrito
	RespawnDelay = 1.2, -- segundos hasta que sale el carrito vacío
}
