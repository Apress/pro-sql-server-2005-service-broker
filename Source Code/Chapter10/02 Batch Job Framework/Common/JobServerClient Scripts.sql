-- Creating a new database for the Job Server client
CREATE DATABASE SSB_JobServerClient
GO

-- Use the new database
USE SSB_JobServerClient
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

-- Create the Job Server client queue
CREATE QUEUE [TaskResponseQueue]
	WITH STATUS = ON
GO

-- Create the Job Server client service
CREATE SERVICE [http://ssb.csharp.at/JobServer/TaskSubmissionService]
ON QUEUE [TaskResponseQueue]
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

-- Register the Managed Stored Procedure "ProcessJobServerTasks"
CREATE PROCEDURE ProcessJobServerTasks
(
	@Message XML,
	@ConversationHandle UNIQUEIDENTIFIER
)
AS
EXTERNAL NAME [JobServer.Implementation].[JobServer.Implementation.JobServer].ProcessJobServerTasks
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
		FROM [TaskResponseQueue]

		IF @conversationHandle IS NOT NULL
		BEGIN
			EXECUTE dbo.ProcessJobServerTasks @messageBody, @conversationHandle;
		END

		COMMIT TRANSACTION
	END TRY
	BEGIN CATCH
		-- Log error (eg. in an error table)
		PRINT ERROR_MESSAGE()
		ROLLBACK TRANSACTION
	END CATCH
GO

-- Activating the stored procedure on the incoming queue
ALTER QUEUE [TaskResponseQueue]
WITH ACTIVATION
(
	PROCEDURE_NAME = sp_ProcessTaskSubmissions,
	MAX_QUEUE_READERS = 1,
	STATUS = ON,
	EXECUTE AS SELF
)
GO

-- Activate the queue
ALTER QUEUE [TaskResponseQueue]
WITH STATUS = ON
GO

-- Sending a Job Server request to the service
BEGIN TRANSACTION
DECLARE @conversationHandle UNIQUEIDENTIFIER

BEGIN DIALOG @conversationHandle
	FROM SERVICE [http://ssb.csharp.at/JobServer/TaskSubmissionService]
	TO SERVICE 'http://ssb.csharp.at/JobServer/TaskProcessingService'
	ON CONTRACT [http://ssb.csharp.at/JobServer/SubmitTaskContract]
	WITH ENCRYPTION = OFF;

SEND ON CONVERSATION @conversationHandle
	MESSAGE TYPE [http://ssb.csharp.at/JobServer/TaskRequestMessage]
	(
		CAST('
			<TaskRequest 
				xmlns="http://ssb.csharp.at/JobServer/TaskRequest"
				Submittor="win2003dev\Klaus Aschenbrenner"
				SubmittedTime="12.12.2006 14:23:45"
				ID="D8E97781-0151-4DBF-B983-F1B4AE6F2445"
				MachineName="win2003dev"
				MessageTypeName="http://ssb.csharp.at/JobServer/TaskRequest">
				<TaskData>
					<ContentOfTheCustomTask>
						<FirstElement>This is my first element</FirstElement>
						<SecondElement>This is my second element</SecondElement>
						<ThirdElement>This is my third element</ThirdElement>
					</ContentOfTheCustomTask>
				</TaskData>
			</TaskRequest>
			'
		AS XML)
	)
COMMIT
GO

-- Verify if the message hasn't been send
SELECT CAST(transmission_status AS nvarchar(max)), * FROM sys.transmission_queue
GO

-- =====================================================
-- Create the necessary routes for the Job Server client
-- =====================================================

-- Route for outbound messages (on the JobServerClient)
SELECT service_broker_guid FROM LOCALHOST.master.sys.databases WHERE name = 'SSB_JobServerService'
GO

CREATE ROUTE JobServerServiceRoute
	WITH SERVICE_NAME = 'http://ssb.csharp.at/JobServer/TaskProcessingService',
	BROKER_INSTANCE = 'E3B7805C-4356-47C2-B119-555FC6217591', -- column "service_broker_guid" from above
	ADDRESS = 'TCP://127.0.0.1:4743'
GO

-- Route for inbound messages (on the JobServerClient)
SELECT service_broker_guid FROM master.sys.databases WHERE name = 'msdb'
GO

CREATE ROUTE JobServerClientRoute
	WITH SERVICE_NAME = 'http://ssb.csharp.at/JobServer/TaskSubmissionService',
	BROKER_INSTANCE = '1D2AAC8C-51C3-4369-9D6E-BEEA8671B8F4', -- column "service_broker_guid" from above
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

-- Create a new certificate for the JobServerClient
CREATE CERTIFICATE JobServerClientCertPrivate
WITH SUBJECT = 'ForJobServerServiceAuthentication',
START_DATE = '01/01/2006'
GO

-- Create the SSB endpoint for the Job Server client
CREATE ENDPOINT JobServerClientEndpoint
STATE = STARTED
AS TCP (LISTENER_PORT = 4089)
FOR SERVICE_BROKER (AUTHENTICATION = CERTIFICATE JobServerClientCertPrivate)
GO

-- Backup the public key of the certificate to the filesystem
-- This certificate is used by the Job Server Service
BACKUP CERTIFICATE JobServerClientCertPrivate TO FILE = 'd:\Klaus\JobServerClientCertPrivate.cert'
GO

-- ======================================================================================================
-- Create the necessary login/user and associate them the public key of the Job Server client certificate
-- ======================================================================================================

-- Create login for the JobServerService
CREATE LOGIN JobServerServiceLogin WITH PASSWORD = 'password1!'
GO

-- Create user for the JobServerService
CREATE USER JobServerServiceUser FOR LOGIN JobServerServiceLogin
GO

-- Create a certificate with the public key of the JobServerService (on the JobServerClient)
CREATE CERTIFICATE JobServerServiceCertPublic
AUTHORIZATION JobServerServiceUser
FROM FILE = 'c:\JobServerServiceCertPrivate.cert'
GO

-- Grant the CONNECT permission to the JobServerService login so that he can connect to the JobServerClient endpoint
GRANT CONNECT ON ENDPOINT::JobServerClientEndpoint TO JobServerServiceLogin
GO

USE SSB_JobServerClient
GO

-- Verify that the message has been send to the Job Server service (automatically in the background)
SELECT CAST(transmission_status AS nvarchar(max)), * FROM sys.transmission_queue
GO

-- Sending a new Job Server request to the service
BEGIN TRANSACTION
DECLARE @conversationHandle UNIQUEIDENTIFIER

BEGIN DIALOG @conversationHandle
	FROM SERVICE [http://ssb.csharp.at/JobServer/TaskSubmissionService]
	TO SERVICE 'http://ssb.csharp.at/JobServer/TaskProcessingService'
	ON CONTRACT [http://ssb.csharp.at/JobServer/SubmitTaskContract]
	WITH ENCRYPTION = OFF;

SEND ON CONVERSATION @conversationHandle
	MESSAGE TYPE [http://ssb.csharp.at/JobServer/TaskRequestMessage]
	(
		CAST('
			<TaskRequest 
				xmlns="http://ssb.csharp.at/JobServer/TaskRequest"
				Submittor="win2003dev\Klaus Aschenbrenner"
				SubmittedTime="12.12.2006 14:23:45"
				ID="D8E97781-0151-4DBF-B983-F1B4AE6F2445"
				MachineName="win2003dev"
				MessageTypeName="http://ssb.csharp.at/JobServer/TaskRequest">
				<TaskData>
					<ContentOfTheCustomTask>
						<FirstElement>This is my first element</FirstElement>
						<SecondElement>This is my second element</SecondElement>
						<ThirdElement>This is my third element</ThirdElement>
					</ContentOfTheCustomTask>
				</TaskData>
			</TaskRequest>
			'
		AS XML)
	)
COMMIT
GO

select * from taskresponsequeue

select * from sys.service_queues

receive * from taskresponsequeue

select * from sys.conversation_endpoints

select * from sys.transmission_queue

select * from sys.dm_broker_connections

end conversation '28C8BAC0-AC50-DB11-A2C6-0080C81899BB'

sp_ProcessTaskSubmissions