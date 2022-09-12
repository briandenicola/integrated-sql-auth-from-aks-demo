using Microsoft.Data.SqlClient;

var connectionString = Environment.GetEnvironmentVariable("SQL_CON_STR", EnvironmentVariableTarget.Process) ?? null;

if( connectionString is null ) throw new ArgumentException("No Connection String defined. Please define environment variable SQL_CON_STR with the proper connection string");

using (SqlConnection connection = new SqlConnection(connectionString))
{
    Console.WriteLine("\nQuery data example:");
    Console.WriteLine("=========================================\n");
    
    connection.Open();       

    String sql = "SELECT Name, IsComplete FROM todos";

    using (SqlCommand command = new SqlCommand(sql, connection))
    {
        using (SqlDataReader reader = command.ExecuteReader())
        {
            while (reader.Read())
            {
                Console.WriteLine("{0} {1}", reader.GetString(0), reader.GetBoolean(1).ToString());
            }
        }
    }                    
}

Console.WriteLine("\nDone. Press enter.");
Console.ReadLine(); 
