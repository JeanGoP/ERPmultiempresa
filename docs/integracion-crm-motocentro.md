# Integración piloto CRM → ERP: Motocentro

La primera entrega recibe una solicitud de crédito aprobada del CRM como venta pendiente de revisión. No crea factura, asiento, cartera ni movimiento de inventario.

## Identidad y correspondencias

- Empresa CRM: Motocentro (`Guid`), empresa ERP: Motocentro (`bigint`). La correspondencia se configura de forma explícita y se comprueba en ambos extremos; nunca se infiere solo del nombre durante un envío.
- Antes de habilitar el envío hay que confirmar el NIT y los dos identificadores internos. El nombre visible aportado por el usuario sirve para localizar las empresas, no como clave definitiva.
- La solicitud CRM y el evento de envío conservan identificadores estables. El ERP rechaza un segundo evento con el mismo identificador si el contenido cambió; un reintento idéntico devuelve la misma recepción.
- Cliente: tipo y número de identificación; artículo: referencia o código; punto de venta: código de sede. Si falta homologación, la ficha queda pendiente y no avanza a facturación.

## Contrato de recepción propuesto

El sobre incluye versión, ID del evento, ID de empresa CRM, ID de solicitud, número, fecha de aprobación, cliente, artículos, valores pactados, cuota inicial, plazo, primer vencimiento, asesor y punto de venta. No incluye documentos, consultas de centrales de riesgo ni datos de codeudores en esta primera fase.

El ERP responde con ID de recepción, estado y posibles campos pendientes. El CRM guarda el resultado y permite reintentar fallas de transporte sin duplicar fichas.

No se habilita el envío productivo mientras falten la correspondencia de empresa, la URL HTTPS de la API ERP o la credencial de servicio.

## Seguridad y transición

La comunicación es backend a backend por HTTPS, con credencial de servicio propia y ámbito limitado a la empresa ERP configurada. El ERP mantiene sus validaciones de precio, inventario y autorización. Facturar continúa siendo una acción independiente de un usuario autorizado en el ERP.
