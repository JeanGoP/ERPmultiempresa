# Retenciones al leer XML

Se excluyen automáticamente tarifas estrictamente inferiores al 2%, tanto en encabezado como en líneas, incluyendo retenciones identificadas dentro de TaxTotal. El 2% exacto se conserva. Si falta tarifa, se calcula solo cuando el componente informa su propia base; sin tarifa ni base se mantiene el importe para revisión. Los campos personalizados no vuelven a incorporar retenciones excluidas de los componentes estándar.

La tarjeta **Retenciones** del resumen superior siempre está visible y es editable, incluso en cero. Las líneas permanecen de solo lectura. Un ajuste manual no vuelve a pasar por el filtro de porcentaje: es una decisión explícita del usuario.

Al editar el total se distribuye internamente entre las líneas, proporcionalmente a su valor más impuestos, conciliando centavos, para utilizar los campos existentes de guardado. Se actualizan el resumen, el detalle de retenciones y el total a pagar por la diferencia. La lectura inicial respeta el total a pagar informado en el XML, sin descontar ni sumar automáticamente las retenciones excluidas. El XML original no se modifica. Se rechazan valores negativos, no finitos o superiores a los límites del documento. La edición se bloquea después de guardar.

Validaciones: `npm test` y `node tests/xml-retention-smoke.js`.
