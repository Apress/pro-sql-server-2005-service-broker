using System;
using System.IO;
using System.Xml;
using System.Data;
using System.Data.SqlClient;
using System.Data.SqlTypes;
using Microsoft.SqlServer.Server;

public partial class StoredProcedures
{
    /// <summary>
    /// This Managed Stored Procedure is activated as soon as a new Service Broker message is arriving in the service queue.
    /// </summary>
    [Microsoft.SqlServer.Server.SqlProcedure]
    public static void ProcessInsertedCustomer()
    {
        // T-SQL statement for reading the Service Broker message out of the service queue
        string sql = "RECEIVE conversation_handle, CAST(message_body AS NVARCHAR(MAX)) FROM [CustomerInsertedServiceQueue]";
        string message = string.Empty;

        using (SqlConnection cnn = new SqlConnection("context connection=true;"))
        {
            try
            {
                // Reading the received Service Broker message
                cnn.Open();
                SqlDataReader reader = new SqlCommand(sql, cnn).ExecuteReader();

                if (reader.Read())
                {
                    // Getting the data from the Service Broker message
                    Guid conversationHandle = (Guid)reader[0];
                    message = (string)reader[1];
                    reader.Close();

                    // Closing the Service Broker conversation
                    new SqlCommand("END CONVERSATION '" + conversationHandle.ToString() + "'", cnn).ExecuteNonQuery();
                }
            }
            finally
            {
                cnn.Close();
            }
        }

        // Writing the message to the file system
        if (message != string.Empty)
            WriteCustomerDetails(message);
    }

    /// <summary>
    /// This method writes the Service Broker message to the file system. So the Managed Assembly needs the permission set EXTERNAL ACCESS.
    /// </summary>
    /// <param name="xmlMessage"></param>
    private static void WriteCustomerDetails(string xmlMessage)
    {
        // Loading the message into a XmlDocument
        XmlDocument xmlDoc = new XmlDocument();
        xmlDoc.LoadXml(xmlMessage);

        // Appening data to the text file
        using (StreamWriter writer = new StreamWriter(@"c:\InsertedCustomers.txt", true))
        {
            // Writing the message to the file system
            writer.WriteLine("New Customer arrived:");
            writer.WriteLine("=====================");
            writer.WriteLine("CustomerNumber: " + xmlDoc.SelectSingleNode("//CustomerNumber").InnerText);
            writer.WriteLine("CustomerName: " + xmlDoc.SelectSingleNode("//CustomerName").InnerText);
            writer.WriteLine("CustomerAddress: " + xmlDoc.SelectSingleNode("//CustomerAddress").InnerText);
            writer.WriteLine("EmailAddress: " + xmlDoc.SelectSingleNode("//EmailAddress").InnerText);

            writer.Close();
        }
    }
}