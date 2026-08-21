# Codificación de artículos

## Identidad interna

El ERP asigna un código propio, consecutivo y estable por empresa:

- `MOT-00000001`: motocicleta u otro artículo con control por serial, motor, chasis o VIN.
- `ART-00000001`: artículo inventariable sin control serial.

El consecutivo se administra en `core.Consecutivo`. El usuario no tiene que calcularlo ni escribirlo al importar una factura.

## Código del proveedor

El código informado en el XML no reemplaza el código interno. Se guarda en `comp.HomologacionArticuloProveedor` como equivalencia entre:

`empresa + proveedor + código externo -> artículo interno`

Cuando otra factura del mismo proveedor trae el mismo código externo, se reutiliza el artículo existente. Si el XML no informa código, se genera una huella estable `DESC-XXXXXXXX` basada en la descripción para poder reutilizar la equivalencia.

## Identificadores de unidades

Motor, chasis, VIN y serial identifican cada unidad física. No son códigos de producto y se conservan en las tablas de unidades serializadas. Color y modelo son atributos de la unidad recibida.

## Reglas de seguridad

- Una equivalencia escogida manualmente siempre tiene prioridad sobre la creación automática.
- Los servicios, gastos, fletes y costos de adquisición no crean artículos de inventario.
- Un código externo solo se reutiliza dentro del mismo proveedor y empresa. No se fusionan automáticamente referencias entre proveedores distintos.
- La creación del artículo, la homologación y el documento del proveedor se ejecutan dentro de la misma transacción: si falla el guardado, no quedan artículos huérfanos.
