using System;
using System.Text;
using System.Data;
using System.Data.SqlClient;
using Microsoft.SqlServer.Server;

public partial class Triggers
{
    /// <summary>
    /// This trigger is fired, when a new record is inserted in the table "Customers".
    /// </summary>
    [Microsoft.SqlServer.Server.SqlTrigger(Name = "OnCustomerInserted", Target = "Customers", Event = "FOR INSERT")]
    public static void OnCustomerInserted()
    {
        using (SqlConnection cnn = new SqlConnection("context connection=true;"))
        {
            try
            {
                // Getting the database from the newly created customer record
                SqlCommand cmd = new SqlCommand("SELECT * FROM INSERTED", cnn);
                cnn.Open();

                SqlDataReader reader = cmd.ExecuteReader();

                if (reader.Read())
                {
                    // Send with the inserted data a Servie Broker message
                    SqlCommand sendCmd = new SqlCommand(GetServiceBrokerScript((string)reader[1], (string)reader[2], (string)reader[3], (string)reader[4]), cnn);
                    reader.Close();
                    sendCmd.ExecuteNonQuery();
                }
            }
            finally
            {
                cnn.Close();
            }
        }
    }

    /// <summary>
    /// This method creates the T-SQL statement necessary for sending a Service Broker message.
    /// </summary>
    /// <param name="customerNumber"></param>
    /// <param name="customerName"></param>
    /// <param name="customerAddress"></param>
    /// <param name="emailAddress"></param>
    /// <returns></returns>
    private static string GetServiceBrokerScript(string customerNumber, string customerName, string customerAddress, string emailAddress)
    {
        // Create the request message
        StringBuilder xmlBuilder = new StringBuilder("<InsertedCustomer>");
        xmlBuilder.Append("<CustomerNumber>").Append(customerNumber).Append("</CustomerNumber>");
        xmlBuilder.Append("<CustomerName>").Append(customerName).Append("</CustomerName>");
        xmlBuilder.Append("<CustomerAddress>").Append(customerAddress).Append("</CustomerAddress>");
        xmlBuilder.Append("<EmailAddress>").Append(emailAddress).Append("</EmailAddress>");
        xmlBuilder.Append("</InsertedCustomer>");

        // Create the T-SQL statement for sending the Service Broker message
        StringBuilder sqlBuilder = new StringBuilder("BEGIN TRANSACTION; ");
        sqlBuilder.Append("DECLARE @ch UNIQUEIDENTIFIER; ");
        sqlBuilder.Append("DECLARE @msg NVARCHAR(MAX); ");
        sqlBuilder.Append("BEGIN DIALOG CONVERSATION @ch ");
        sqlBuilder.Append("FROM SERVICE [CustomerInsertedClient] ");
        sqlBuilder.Append("TO SERVICE 'CustomerInsertedService' ");
        sqlBuilder.Append("ON CONTRACT [http://ssb.csharp.at/SSB_Book/c10/CustomerInsertContract] ");
        sqlBuilder.Append("WITH ENCRYPTION=OFF; ");
        sqlBuilder.Append("SET @msg = '").Append(xmlBuilder.ToString()).Append("'; ");
        sqlBuilder.Append("SEND ON CONVERSATION @ch MESSAGE TYPE [http://ssb.csharp.at/SSB_Book/c10/CustomerInsertedRequestMessage] (@msg); ");
        sqlBuilder.Append("COMMIT;");

        // Return the whole T-SQL script
        return sqlBuilder.ToString();
    }
}