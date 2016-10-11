-- Drop Database "SSB_JobServerClient" (with close existing connections) through the UI
-- ...

USE MASTER
GO

-- Drop SSB endpoint
DROP ENDPOINT JobServerClientEndpoint
GO

-- Drop login JobServerServiceLogin
DROP LOGIN JobServerServiceLogin
GO

-- Drop all certificates
DROP CERTIFICATE JobServerClientCertPrivate
GO
DROP CERTIFICATE JobServerServiceCertPublic
GO

-- Drop user JobServerServiceUser
DROP USER JobServerServiceUser
GO

-- Drop the master key
DROP MASTER KEY
GO
