-- Creating the XML Schema collection, which stores the XSD schemas for the SSB messages
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

-- Creating the necessary message types
CREATE MESSAGE TYPE [http://ssb.csharp.at/JobServer/TaskRequestMessage] VALIDATION = VALID_XML WITH SCHEMA COLLECTION JobServerMessages
CREATE MESSAGE TYPE [http://ssb.csharp.at/JobServer/TaskResponseMessage] VALIDATION = VALID_XML WITH SCHEMA COLLECTION JobServerMessages

-- Create the necessary contract which binds the 2 messages together
CREATE CONTRACT [http://ssb.csharp.at/JobServer/SubmitTaskContract]
(
	[http://ssb.csharp.at/JobServer/TaskRequestMessage] SENT BY INITIATOR,
	[http://ssb.csharp.at/JobServer/TaskResponseMessage] SENT BY TARGET
)

-- Create the queues
CREATE QUEUE [TaskSubmissionQueue]
	WITH STATUS = ON
CREATE QUEUE [TaskResponseQueue]
	WITH STATUS = ON

-- Create the services
CREATE SERVICE [http://ssb.csharp.at/JobServer/TaskSubmissionService]
ON QUEUE [TaskResponseQueue]
(
	[http://ssb.csharp.at/JobServer/SubmitTaskContract]
)

CREATE SERVICE [http://ssb.csharp.at/JobServer/TaskProcessingService]
ON QUEUE [TaskSubmissionQueue]
(
	[http://ssb.csharp.at/JobServer/SubmitTaskContract]
)

-- Create service program which is activated on the queue "TaskSubmissionQueue" when a new "TaskRequestMessage" is arriving from a client
CREATE PROCEDURE sp_ProcessTaskSubmissions
AS
	DECLARE @conversationHandle AS UNIQUEIDENTIFIER;
	DECLARE @messageBody as XML;

	BEGIN TRY
		BEGIN TRANSACTION;

		RECEIVE TOP (1)
			@conversationHandle = conversation_handle,
			@messageBody = CAST(message_body AS XML)
		FROM [TaskSubmissionQueue]

		IF @conversationHandle IS NOT NULL
		BEGIN
			EXECUTE dbo.ProcessJobServerTasks @messageBody;
			
			DECLARE @data nvarchar(max)
			SET @data = CAST(@messageBody as nvarchar(max))
			INSERT INTO LogTable VALUES (getdate(), @data);
			END CONVERSATION @conversationHandle;
		END

		COMMIT TRANSACTION
	END TRY
	BEGIN CATCH
		-- Log error (eg. in an error table)
		PRINT ERROR_MESSAGE()
		ROLLBACK TRANSACTION
	END CATCH

-- Activating the stored procedure on the incoming queue
ALTER QUEUE [TaskSubmissionQueue]
	WITH ACTIVATION (DROP)
	(
		PROCEDURE_NAME = sp_ProcessTaskSubmissions,
		MAX_QUEUE_READERS = 1,
		STATUS = ON,
		EXECUTE AS SELF
	)

ALTER QUEUE [TaskSubmissionQueue]
WITH STATUS = ON

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
				MessageTypeName="http://ssb.csharp.at/JobServer/MyCustomTask">
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

-- Route for outbound messages (on the JobServerClient)
create route JobServerServiceRoute
	with service_name = 'http://ssb.csharp.at/JobServer/TaskProcessingService',
	broker_instance = 'B0D6405B-7E7C-4BAC-8A17-E3EDC9E97E03', -- select service_broker_guid from master.sys.databases where name='JobServerService'
	address = 'TCP://127.0.0.1:4743'

-- Route for inbound messages (on the JobServerClient)
create route JobServerClientRoute
	with service_name = 'http://ssb.csharp.at/JobServer/TaskSubmissionService',
	broker_instance = '1D2AAC8C-51C3-4369-9D6E-BEEA8671B8F4', -- select service_broker_guid from master.sys.databases where name='msdb'
	address = 'LOCAL'

-- Route for outbound messages (on the JobServerService)
create route JobServerClientRoute
	with service_name = 'http://ssb.csharp.at/JobServer/TaskSubmissionService',
	broker_instance = '217E4585-1FFD-4B40-89DA-769128AB96DE', -- select service_broker_guid from master.sys.databases where name='JobServerClient'
	address = 'TCP://127.0.0.1:4089'

-- Route for inbound messages (on the JobServerService)
create route JobServerServiceRoute
	with service_name = 'http://ssb.csharp.at/JobServer/TaskProcessingService',
	broker_instance = '49440C16-26F5-441C-A9E8-0B8D6A28661F', -- select service_broker_guid from master.sys.databases where name='msdb'
	address = 'LOCAL'

-- Create Database Master key, so that the private key of the certificate can be encrypted
create master key encryption by password = 'password1!'

-- Create a new certificate for the JobServerClient
create certificate JobServerClientCertPrivate
--authorization dbo
with subject = 'ForJobServerServiceAuthentication',
start_date = '01/01/2006'

-- Backup the public key of the certificate to the filesystem
backup certificate JobServerClientCertPrivate to file = 'c:\JobServerClientCertPrivate.cert'

-- Creating SSB endpoint (on the JobServerClient)
create endpoint JobServerClientEndpoint
state = started
as tcp (listener_port = 4089)
for service_broker (authentication = certificate JobServerClientCertPrivate)

-- Create Database Master key, so that the private key of the certificate can be encrypted
create master key encryption by password = 'password1!'

-- Create a new certificate for the JobServerService
create certificate JobServerServiceCertPrivate
--authorization dbo
with subject = 'ForJobServerClientAuthentication',
start_date = '01/01/2006'

-- Backup the public key of the certificate to the filesystem
backup certificate JobServerServiceCertPrivate to file = 'd:\klaus\JobServerServiceCertPrivate.cert'

-- Creating SSB endpoint (on the JobServerService)
create endpoint JobServerServiceEndpoint
state = started
as tcp (listener_port = 4743)
for service_broker (authentication = certificate JobServerServiceCertPrivate)

-- Create login for the JobServerClient (on the JobServerService)
create login JobServerClient with password = 'password1!'

-- Create user for the JobServerClient (on the JobServerService)
create user JobServerClient for login JobServerClient

-- Create a certificate with the public key of the JobServerClient (on the JobServerService)
create certificate JobServerClientCertPublic
authorization JobServerClient
from file = 'd:\Klaus\JobServerClientCertPrivate.cert'

-- The JobServerClient user can connect to the JobServerService endpoint
grant connect on endpoint::JobServerServiceEndpoint to JobServerClient

-- Create login for the JobServerService (on the JobServerClient)
create login JobServerService with password = 'password1!'

-- Create user for the JobServerService (on the JobServerClient)
create user JobServerService for login JobServerService

-- Create a certificate with the public key of the JobServerService (on the JobServerClient)
create certificate JobServerServiceCertPublic
authorization JobServerService
from file = 'c:\JobServerServiceCertPrivate.cert'

-- The JobServerService user can connect to the JobServerClient endpoint
grant connect on endpoint::JobServerClientEndpoint to JobServerService



grant send on service::[http://ssb.csharp.at/JobServer/TaskProcessingService] to public

select * from sys.certificates

select transmission_status, * from sys.transmission_queue

select * from tasksubmissionqueue

select * from taskresponsequeue

receive * from taskresponsequeue

select * from sys.service_broker_endpoints

select * from sys.dm_broker_connections

select cast(message_body as xml), * from taskresponsequeue

receive * from tasksubmissionqueue

sp_ProcessTaskSubmissions

select * from logtable

delete from logtable




ALTER QUEUE [TaskSubmissionQueue]
	WITH ACTIVATION --(DROP)
	(
		PROCEDURE_NAME = sp_ProcessTaskSubmissions,
		MAX_QUEUE_READERS = 1,
		STATUS = ON,
		EXECUTE AS SELF
	)

ALTER QUEUE [TaskSubmissionQueue]
WITH STATUS = ON