-- Doble SQL de contrato, SOLO en la base LocalDB desechable de pruebas.
-- No reemplaza una prueba contra los procedimientos originales de Zeus.
CREATE TABLE dbo.MAECONT(CODICTA varchar(16),DESCCTA varchar(40),IDBANCO varchar(3),INDCPICTA int,CTACORRIENTE varchar(25),HABILITARCTA int,TIPOCTA char(1),INDCCOCTA int,ExigeItem int,PORCEIMPUESTO decimal(18,4),IndValorRetenido int);
INSERT dbo.MAECONT VALUES('111005','Banco','001',1,'123456',1,'D',0,0,0,0),('220501','Proveedor',NULL,3,NULL,1,'D',0,0,0,0),('519595','Gastos',NULL,1,NULL,1,'D',0,0,0,0),('110505','Caja',NULL,6,'',1,'D',0,0,0,0);
ALTER TABLE dbo.MAECONT ADD IDMONEDA varchar(3) NULL;
CREATE TABLE dbo.MONEDAS(IDMONEDA varchar(3),DESCRIP varchar(40),SIMONEDA int,Deshabilitado int);
INSERT dbo.MONEDAS VALUES('TRA','Transferencia',7,0),('EFE','Efectivo',0,0);
CREATE TABLE dbo.FUENTES(IDFUENTE char(2),IDTIPDOC char(3),Deshabilitado int);
INSERT dbo.FUENTES VALUES('05','003',0),('12','001',0);
CREATE TABLE dbo.TERCEROS(IDTERCERO varchar(10),Deshabilitado int);
CREATE TABLE dbo.PROVEEDORES(IDPROVE varchar(10),IDTERCERO varchar(10),Deshabilitado int);
INSERT dbo.TERCEROS VALUES('123',0);INSERT dbo.PROVEEDORES VALUES('123','123',0);
CREATE TABLE dbo.Facturas_Bu(Anomesfac varchar(6),IdCliprv varchar(10),Codicta varchar(16),tipofact varchar(2),numefac varchar(20),refefac varchar(25),Idunidad varchar(3),Bu varchar(25),Sactfac decimal(18,2));
INSERT dbo.Facturas_Bu VALUES('202609','123','220501','FA','F1','','','Local',-1000);
CREATE TABLE dbo.DOCUMENT(NUMEDCTO varchar(10),FNTEDCTO varchar(2),FECHDCTO varchar(10),SUDBDCTO decimal(18,2),SUCRDCTO decimal(18,2),DESCDCTO varchar(120),XmlAdicionales nvarchar(max));
CREATE TABLE dbo.TRANSAC(IDFUENTE varchar(2),NUMDOCTRA varchar(10),CODICTA varchar(16),VALORTRA decimal(18,2),BU varchar(25),CLIPRV varchar(10),NITTRA varchar(10),TIPOFAC varchar(3),NUMEFAC varchar(20),REFEFAC varchar(25),INDCPITRA varchar(1),STATUSTRA varchar(2));
CREATE TABLE dbo.EgresoTestControl(UpdateBalance bit NOT NULL);
INSERT dbo.EgresoTestControl VALUES(1);
GO
CREATE PROCEDURE dbo.spWSG_Contabilidad @Iden int,@XML varchar(max) AS
BEGIN
    DECLARE @x xml=CONVERT(xml,@XML),@n varchar(10)=RIGHT('0000000000'+CONVERT(varchar(10),(SELECT COUNT(*)+1 FROM dbo.DOCUMENT)),10);
    INSERT dbo.TRANSAC SELECT t.n.value('IDFUENTE[1]','varchar(2)'),@n,t.n.value('CODICTA[1]','varchar(16)'),t.n.value('VALORTRA[1]','decimal(18,2)'),t.n.value('BU[1]','varchar(25)'),t.n.value('CLIPRV[1]','varchar(10)'),t.n.value('NITTRA[1]','varchar(10)'),t.n.value('TIPOFAC[1]','varchar(3)'),t.n.value('NUMEFAC[1]','varchar(20)'),t.n.value('REFEFAC[1]','varchar(25)'),t.n.value('INDCPITRA[1]','varchar(1)'),'AC' FROM @x.nodes('/ZEUS_SQL/Documento/Transac') t(n);
    INSERT dbo.DOCUMENT SELECT @n,h.n.value('FNTEDCTO[1]','varchar(2)'),h.n.value('FECHDCTO[1]','varchar(10)'),(SELECT SUM(VALORTRA) FROM dbo.TRANSAC WHERE NUMDOCTRA=@n AND VALORTRA>0),-(SELECT SUM(VALORTRA) FROM dbo.TRANSAC WHERE NUMDOCTRA=@n AND VALORTRA<0),h.n.value('DESCDCTO[1]','varchar(120)'),h.n.value('XmlAdicionales[1]','nvarchar(max)') FROM @x.nodes('/ZEUS_SQL/Documento/Document') h(n);
    IF EXISTS(SELECT 1 FROM dbo.EgresoTestControl WHERE UpdateBalance=1)
        UPDATE f SET Sactfac=Sactfac+t.VALORTRA FROM dbo.Facturas_Bu f JOIN dbo.TRANSAC t ON t.CODICTA=f.Codicta AND t.CLIPRV=f.IdCliprv AND t.TIPOFAC=f.tipofact AND t.NUMEFAC=f.numefac AND t.REFEFAC=f.refefac AND t.BU=f.Bu WHERE t.NUMDOCTRA=@n AND t.INDCPITRA='3';
    RETURN 0;
END;
GO
