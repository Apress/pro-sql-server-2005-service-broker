-- Creating a new database for the Job Server Service
CREATE DATABASE SSB_JobServerService
GO

-- Use the new database
USE SSB_JobServerService
GO

-- Creating the XML Schema collection, which stores the XSD schemas for the Job Server messages
CREATE XML SCHEMA COLLECTION JobServerMessages AS
'
<!-- Request message send from the client to the Job Server -->
<xs:schema 
	targetNamespace="http://ssb.csharp.at/JobServer/TaskRequest" 
	elementFormDefault="qualified" 
	xmlns="http://tempuri.org/XMLSchema.xsd" 
	xmlns:mstns="http://ssb.csharp.at/JobServer/TaskRequest" 
	xmlns:xs="http://www.w3.org/2001/XMLSchema">
	<xs:element name="TaskRequest">
		<xs:complexType>
			<xs:sequence>
				<xs:element name="TaskData" minOccurs="0" maxOccurs="1">
					<xs:complexType>
						<xs:sequence>
							<xs:any namespace="##any" minOccurs="0" maxOccurs="1" processContents="skip" />
						</xs:sequence>
					</xs:complexType>
				</xs:element>
			</xs:sequence>
			<xs:attribute name="Submittor" type="xs:string" />
			<xs:attribute name="SubmittedTime" type="xs:string" />
			<xs:attribute name="ID" type="xs:string" />
			<xs:attribute name="MachineName" type="xs:string" />
			<xs:attribute name="MessageTypeName" type="xs:string" />
		</xs:complexType>
	</xs:element>
</xs:schema>
<!-- Response message send from the Job Server to the client -->
<xs:schema 
	targetNamespace="http://ssb.csharp.at/JobServer/TaskResponse" 
	elementFormDefault="qualified" 
	xmlns="http://tempuri.org/XMLSchema.xsd" 
	xmlns:mstns="http://ssb.csharp.at/JobServer/TaskResponse" 
	xmlns:xs="http://www.w3.org/2001/XMLSchema">
	<xs:element name="TaskResponse">
		<xs:complexType>
			<xs:attribute name="ID" type="xs:string" />
		</xs:complexType>
	</xs:element>
</xs:schema>
'
GO

-- Creating the necessary message types
CREATE MESSAGE TYPE [http://ssb.csharp.at/JobServer/TaskRequestMessage] VALIDATION = VALID_XML WITH SCHEMA COLLECTION JobServerMessages
CREATE MESSAGE TYPE [http://ssb.csharp.at/JobServer/TaskResponseMessage] VALIDATION = VALID_XML WITH SCHEMA COLLECTION JobServerMessages
GO

-- Create the necessary contract which binds the 2 messages together
CREATE CONTRACT [http://ssb.csharp.at/JobServer/SubmitTaskContract]
(
	[http://ssb.csharp.at/JobServer/TaskRequestMessage] SENT BY INITIATOR,
	[http://ssb.csharp.at/JobServer/TaskResponseMessage] SENT BY TARGET
)
GO

-- Create the Job Server Service queue
CREATE QUEUE [TaskSubmissionQueue]
	WITH STATUS = ON
GO

-- Create the Job Server Service
CREATE SERVICE [http://ssb.csharp.at/JobServer/TaskProcessingService]
ON QUEUE [TaskSubmissionQueue]
(
	[http://ssb.csharp.at/JobServer/SubmitTaskContract]
)
GO

-- Register the Managed Assembly which does the processing of the submitted Job Server messages
CREATE ASSEMBLY [JobServer.Implementation]
FROM 'd:\Klaus\Work\Private\Apress\Pro SQL 2005 Service Broker\Chapter 12\Samples\JobServer\JobServer.Implementation\bin\Debug\JobServer.Implementation.dll'
GO

-- Add the debug information about the assembly
ALTER ASSEMBLY  [JobServer.Implementation]
ADD FILE FROM 'd:\Klaus\Work\Private\Apress\Pro SQL 2005 Service Broker\Chapter 12\Samples\JobServer\JobServer.Implementation\bin\Debug\JobServer.Implementation.pdb'
GO

-- Validate the registration of the Managed Assemblies
SELECT * FROM sys.assemblies
GO

-- Register the Managed Stored Procedure "ProcessJobServerTasks"
CREATE PROCEDURE ProcessJobServerTasks
(
	@Message XML,
	@ConversationHandle UNIQUEIDENTIFIER
)
AS
EXTERNAL NAME [JobServer.Implementation].[JobServer.Implementation.JobServer].ProcessJobServerTasks
GO

-- Create a logging table which stores all processed Service Broker messages
CREATE TABLE LogTable
(
	Date datetime,
	LogData nvarchar(max)
)
GO

-- Create the service program which is activated on the queue "TaskSubmissionQueue" when a new "TaskRequestMessage" arrives from a client
CREATE PROCEDURE sp_ProcessTaskSubmissions
AS
	DECLARE @conversationHandle AS UNIQUEIDENTIFIER;
	DECLARE @messageBody AS XML;

	BEGIN TRY
		BEGIN TRANSACTION;

		RECEIVE TOP (1)
			@conversationHandle = conversation_handle,
			@messageBody = CAST(message_body AS XML)
		FROM [TaskSubmissionQueue]

		IF @conversationHandle IS NOT NULL
		BEGIN
			EXECUTE dbo.ProcessJobServerTasks @messageBody, @conversationHandle;
			
			DECLARE @data nvarchar(max)
			SET @data = CAST(@messageBody as nvarchar(max))
			INSERT INTO LogTable VALUES (getdate(), @data);
		END

		COMMIT TRANSACTION
	END TRY
	BEGIN CATCH
		-- Log error (eg. in an error table)
		PRINT ERROR_MESSAGE()
		ROLLBACK TRANSACTION
	END CATCH
GO

-- Create the factory lookup table
CREATE TABLE JobServerTasks
(
	ID uniqueidentifier NOT NULL,
	MessageType nvarchar(255) NOT NULL,
	TypeName nvarchar(255) NOT NULL,
CONSTRAINT [PK_JobServerTasks] PRIMARY KEY CLUSTERED 
(
	ID ASC
)
WITH 
(
	PAD_INDEX  = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) 
ON [PRIMARY]
GO

-- Insert the available JobServer tasks in the factory lookup table
INSERT INTO JobServerTasks (ID, MessageType, TypeName)
VALUES (NEWID(), 'http://ssb.csharp.at/JobServer/TaskRequest', 'JobServer.Implementation.DoNothingTask,JobServer.Implementation, Version=1.0.0.0,Culture=neutral, PublicKeyToken=neutral')
INSERT INTO JobServerTasks (ID, MessageType, TypeName)
VALUES (NEWID(), 'http://schemas.microsoft.com/SQL/ServiceBroker/Error', 'JobServer.Implementation.DoNothingTask,JobServer.Implementation, Version=1.0.0.0,Culture=neutral, PublicKeyToken=neutral')
GO

-- Activating the stored procedure on the incoming queue
ALTER QUEUE [TaskSubmissionQueue]
WITH ACTIVATION
(
	PROCEDURE_NAME = sp_ProcessTaskSubmissions,
	MAX_QUEUE_READERS = 1,
	STATUS = ON,
	EXECUTE AS SELF
)
GO

-- Activate the queue
ALTER QUEUE [TaskSubmissionQueue]
WITH STATUS = ON
GO

-- ======================================================
-- Create the necessary routes for the Job Server service
-- ======================================================
SELECT service_broker_guid FROM [LOCALHOST\SQLEXPRESS].master.sys.databases WHERE name = 'SSB_JobServerClient'
GO

-- Route for outbound messages
CREATE ROUTE JobServerClientRoute
	WITH SERVICE_NAME = 'http://ssb.csharp.at/JobServer/TaskSubmissionService',
	BROKER_INSTANCE = '30B086BC-603A-41FC-BA69-9994F6A02FEA', -- column "service_broker_guid" from above
	ADDRESS = 'TCP://127.0.0.1:4089'
GO

-- Route for inbound messages
SELECT service_broker_guid FROM master.sys.databases WHERE name = 'msdb'
GO

CREATE ROUTE JobServerServiceRoute
	WITH SERVICE_NAME = 'http://ssb.csharp.at/JobServer/TaskProcessingService',
	BROKER_INSTANCE = '49440C16-26F5-441C-A9E8-0B8D6A28661F', -- column "service_broker_guid" from above
	ADDRESS = 'LOCAL'
GO

-- Drop the standard route (only for development purposes)
DROP ROUTE AutoCreatedLocal
GO

-- =================================================================================
-- Create the necessary certificates and the SSB endpoint for the transport security
-- =================================================================================
USE master
GO

-- Create Database Master key, so that the private key of the certificate can be encrypted
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'password1!'
GO

-- Create a new certificate for the JobServerService
CREATE CERTIFICATE JobServerServiceCertPrivate
WITH SUBJECT = 'ForJobServerClientAuthentication',
START_DATE = '01/01/2006'
GO

-- Creating SSB endpoint for the Job Server service
CREATE ENDPOINT JobServerServiceEndpoint
STATE = STARTED
AS TCP (LISTENER_PORT = 4743)
FOR SERVICE_BROKER (AUTHENTICATION = CERTIFICATE JobServerServiceCertPrivate)
GO

-- Backup the public key of the certificate to the filesystem
-- This certificate is used by the Job Server client
BACKUP CERTIFICATE JobServerServiceCertPrivate TO FILE = 'd:\klaus\JobServerServiceCertPrivate.cert'
GO

-- ======================================================================================================
-- Create the necessary login/user and associate them the public key of the Job Server client certificate
-- ======================================================================================================

-- Create a login for the JobServerClient
CREATE LOGIN JobServerClientLogin WITH PASSWORD = 'password1!'
GO

-- Create a user for the JobServerClient
CREATE USER JobServerClientUser FOR LOGIN JobServerClientLogin
GO

-- Create a certificate with the public key of the JobServerClient and associate it with the previous created user
CREATE CERTIFICATE JobServerClientCertPublic
AUTHORIZATION JobServerClientUser
FROM FILE = 'd:\Klaus\JobServerClientCertPrivate.cert'
GO

-- Grant the CONNECT permission to the JobServerClient login so that he can connect to the JobServerService endpoint
GRANT CONNECT ON ENDPOINT::JobServerServiceEndpoint TO JobServerClientLogin
GO

USE SSB_JobServerService
GO

GRANT SEND ON SERVICE::[http://ssb.csharp.at/JobServer/TaskProcessingService] TO PUBLIC
GO

select * from tasksubmissionqueue

receive * from tasksubmissionqueue

select * from sys.transmission_queue

sp_processtasksubmissions

select * from logtable

delete from LogTable

select * from sys.conversation_endpoints

select * from sys.service_queues
