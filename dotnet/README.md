# DWX_Connect - a simple multi-language MT4 connector

DWX_Connect provides functions to subscribe to tick and bar data, as well as to trade on MT4 or MT5 via python, java and C#. Its simple file-based communication also provides an easy starting point for implementations in other programming languages.


## First steps for C#

1. Download the code from the DWX_Connect GitHub repository.

1. Copy the server EA (DWX_Server_MT4.mq4 or DWX_Server_MT5.mq5) into the /MQL4/Experts or /MQL5/Experts directory (File -> Open Data Folder).

1. Double click on the MT4/MT5 EA file to open it in MetaEditor. Press F7 to compile the file. Restart MT4/MT5 or rightclick -> Refresh in the Navigator window.

1. Attach the EA to any chart. Change the input parameters if needed, for example, MaximumOrders and MaximumLotSize if you want to trade larger sizes.

1. Copy the content of the dotnet/DWX_Connect directory into your working directory. You can use DWXExampleClient.cs as a starting point for your own algorithm. 

1. To compile and run the code, you can either use Visual Studio, or compile thourgh the command line with:

    ```console
    dotnet build
    ```

1. The example application will try to subscribe to EURUSD and GBPUSD (as well as some bar data) and print some information on every new tick or bar. Run the application with:

    ```console
    dotnet run
    ```

 
