USE master;

IF EXISTS (SELECT * FROM sys.databases WHERE name = 'Chapter10_AsynchronousTrigger')
BEGIN
	PRINT 'Dropping database ''Chapter10_AsynchronousTrigger''';
	DROP DATABASE Chapter10_AsynchronousTrigger;
END
GO

CREATE DATABASE Chapter10_AsynchronousTrigger
GO

USE Chapter10_AsynchronousTrigger
GO

CREATE TABLE [dbo].[Customers](
	[ID] [uniqueidentifier] NOT NULL,
	[CustomerNumber] [varchar](100) NOT NULL,
	[CustomerName] [varchar](100) NOT NULL,
	[CustomerAddress] [varchar](100) NOT NULL,
	[EmailAddress] [varchar](100) NOT NULL,
 CONSTRAINT [PK_Customers] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

-- Setting the Trustworthy property for assemblies with EXTERNAL ACCESS permissions
ALTER DATABASE Chapter10_AsynchronousTrigger SET TRUSTWORTHY ON
GO

-- Import assembly into the database
CREATE ASSEMBLY [CustomerManagement]
FROM 'D:\Klaus\Work\Private\Apress\Pro SQL 2005 Service Broker\Chapter 10\Samples\01 Asynchronous Trigger\AsynchronousTrigger\bin\Debug\AsynchronousTrigger.dll'
WITH PERMISSION_SET = EXTERNAL_ACCESS
GO

-- Create the managed stored procedure
CREATE PROCEDURE [ProcessInsertedCustomer]
AS EXTERNAL NAME [CustomerManagement].[StoredProcedures].[ProcessInsertedCustomer]
GO

-- Create the managed trigger
CREATE TRIGGER [OnCustomerInserted] ON [Customers] FOR INSERT
AS EXTERNAL NAME [CustomerManagement].[Triggers].[OnCustomerInserted]
GO

-- Create the request message type
CREATE MESSAGE TYPE 
  [http://ssb.csharp.at/SSB_Book/c10/CustomerInsertedRequestMessage]
  VALIDATION = WELL_FORMED_XML
GO

-- Create the response message type
CREATE MESSAGE TYPE
	[http://ssb.csharp.at/SSB_Book/c10/CustomerInsertedResponseMessage]
	VALIDATION = WELL_FORMED_XML
GO

-- Create the contract based on the previous 2 message types
CREATE CONTRACT [http://ssb.csharp.at/SSB_Book/c10/CustomerInsertContract]
(
    [http://ssb.csharp.at/SSB_Book/c10/CustomerInsertedRequestMessage] SENT BY INITIATOR,
    [http://ssb.csharp.at/SSB_Book/c10/CustomerInsertedResponseMessage] SENT BY TARGET
)
GO

-- Create the service queue
CREATE QUEUE [CustomerInsertedServiceQueue]
GO

-- Create the client queue
CREATE QUEUE [CustomerInsertedClientQueue]
GO

-- Create the service
CREATE SERVICE [CustomerInsertedService] 
	ON QUEUE [CustomerInsertedServiceQueue]
(
	[http://ssb.csharp.at/SSB_Book/c10/CustomerInsertContract]
)
GO

-- Create the client service
CREATE SERVICE [CustomerInsertedClient]
	ON QUEUE [CustomerInsertedClientQueue]
(
	[http://ssb.csharp.at/SSB_Book/c10/CustomerInsertContract]
)
GO

-- Activate internal activation
ALTER QUEUE [CustomerInsertedServiceQueue]
WITH ACTIVATION 
(
	STATUS = ON,
	PROCEDURE_NAME = ProcessInsertedCustomer,
	MAX_QUEUE_READERS = 1,
	EXECUTE AS SELF
)
GO

-- Try to insert a new record into the table.
-- As soon as the record is inserted into the table, the managed trigger does his work and the text file is created in the file system
INSERT INTO Customers (ID, CustomerNumber, CustomerName, CustomerAddress, EmailAddress)
VALUES (NEWID(), 'AKS', 'Aschenbrenner Klaus', 'A-1220 Vienna', 'Klaus.Aschenbrenner@csharp.at')