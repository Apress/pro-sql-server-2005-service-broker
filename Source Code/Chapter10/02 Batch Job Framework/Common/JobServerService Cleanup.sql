-- Drop Database "SSB_JobServerService" (with close existing connections) throug the UI
-- ...

USE MASTER
GO

-- Drop SSB endpoint
DROP ENDPOINT JobServerServiceEndpoint
GO

-- Drop login JobServerServiceLogin
DROP LOGIN JobServerClientLogin
GO

-- Drop all certificates
DROP CERTIFICATE JobServerClientCertPublic
GO
DROP CERTIFICATE JobServerServiceCertPrivate
GO

-- Drop user JobServerServiceUser
DROP USER JobServerClientUser
GO

-- Drop the master key
DROP MASTER KEY
GO
