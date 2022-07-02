"use strict";
/* --------------------------------------------------------------------------------------------
 * Copyright (c) Microsoft Corporation. All rights reserved.
 * Licensed under the MIT License. See License.txt in the project root for license information.
 * ------------------------------------------------------------------------------------------ */
Object.defineProperty(exports, "__esModule", { value: true });
exports.AzureFunctionsService = exports.hostFileName = void 0;
const azureFunctionsContracts = require("../models/contracts/azureFunctions/azureFunctionsContracts");
exports.hostFileName = 'host.json';
/**
 * Adds SQL Bindings to generated Azure Functions in a file
 */
class AzureFunctionsService {
    constructor(_client) {
        this._client = _client;
    }
    /**
     * Adds a SQL Binding to a specified Azure function in a file
     * @param bindingType Type of SQL Binding
     * @param filePath Path of the file where the Azure Functions are
     * @param functionName Name of the function where the SQL Binding is to be added
     * @param objectName Name of Object for the SQL Query
     * @param connectionStringSetting Setting for the connection string
     * @returns
     */
    addSqlBinding(bindingType, filePath, functionName, objectName, connectionStringSetting) {
        const params = {
            bindingType: bindingType,
            filePath: filePath,
            functionName: functionName,
            objectName: objectName,
            connectionStringSetting: connectionStringSetting
        };
        return this._client.sendRequest(azureFunctionsContracts.AddSqlBindingRequest.type, params);
    }
    /**
     * Gets the names of the Azure functions in the file
     * @param filePath Path of the file to get the Azure functions
     * @returns array of names of Azure functions in the file
     */
    getAzureFunctions(filePath) {
        const params = {
            filePath: filePath
        };
        return this._client.sendRequest(azureFunctionsContracts.GetAzureFunctionsRequest.type, params);
    }
}
exports.AzureFunctionsService = AzureFunctionsService;

//# sourceMappingURL=azureFunctionsService.js.map
