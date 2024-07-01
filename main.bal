import ballerina/io;
import ballerina/http;
import ballerina/os;
import ballerina/log;

configurable string solrAdminUsername = "admin";
configurable string solrUrl = "https://bcentral-solrcloud-common";
configurable string solrCreateSchemaPath = "./resources/solr_schema.json";
configurable string solrConfigPath = "./resources/solr_config.json";
configurable string solrDeleteConfigPath = "./resources/delete_solr_config.json";
configurable string solrCollection = "packages";
configurable string solrSymbolsCollection = "symbols";


final http:Client solrClient = check new (solrUrl, auth = {
        username: solrAdminUsername,
        password: os:getEnv("SOLR_ADMIN_PASSWORD")
    },
    secureSocket = {
        enable: false
    },
    timeout = 60
    // retryConfig = {
    //     interval: 3,
    //     count: 3,
    //     backOffFactor: 2.0,
    //     maxWaitInterval: 20
    // }
);

service /solr on new http:Listener(8080) {
    resource function post reset\-solr() returns json {
        error? err = resetSolrIndex();
        if err is error {
            log:printError("error occurred while resetting index: ", err);
            return {"error": err.message()};
        }
        return {"message": "Solr index reset successfully"};
    }

    resource function get solr\-collections() returns SolrCollectionResponse|error {
        return getSolrCollections();
    }
    
}

public isolated function getSolrCollections() returns SolrCollectionResponse|error {
    // Get collection list
    string[] collections = [];
    log:printInfo("Fetching collections in apache solr");
    SolrCollectionResponse|error collectionRes = solrClient->/solr/admin/collections.get(action = "LIST");

    if collectionRes is error {
        return collectionRes;
    }

    collections = collectionRes.collections;
    log:printInfo("Collection in apache solr: " + collections.toString());
    return collectionRes;
}

# Reset the Solr index
#
# + numShards - number of shards
# + replicationFactor - replication factor
# + maxShardsPerNode - maximum shards per node
# + return - error if issue with query, nil otherwise
public isolated function resetSolrIndex(int numShards = 1, int replicationFactor = 1, int maxShardsPerNode = 1) returns error? {
    // Get collection list
    string[] collections = [];
    log:printInfo("Fetching collections in apache solr");
    SolrCollectionResponse|error collectionRes = solrClient->/solr/admin/collections.get(action = "LIST");

    if collectionRes is SolrCollectionResponse {
        collections = collectionRes.collections;
    }
    log:printInfo("Collection in apache solr: " + collections.toString());

    http:Response res;

    // Check if bcentral collection exists
    if (collections.length() != 0) {
        foreach string collection in collections {
            // Delete solrconfig.xml
            json solrConfig = check io:fileReadJson(solrDeleteConfigPath);
            res = check solrClient->/solr/[collection]/config.post(solrConfig);
            log:printInfo("Response received from Solr: " + check res.getTextPayload());

            // Delete all documents
            log:printInfo("Deleting all documents in apache solr collection : " + collection);
            res = check solrClient->/solr/[collection]/update.post({"delete": {"query": "*:*"}}, softCommit = true);
            log:printInfo("Response received from Solr after deleting all documents : " + check res.getTextPayload());

            // Fetch fields from solr
            SolrFieldsResponse fieldsResponse = check solrClient->/solr/[collection]/schema/fields.get();
            SolrField[] fields = fieldsResponse.fields;

            json[] deleteFields = [];
            foreach SolrField 'field in fields {
                if ('field.name != "id" && 'field.name != "_version_" && 'field.name != "_root_" && 'field.name != "_text_" && 'field.name != "_nest_path_") { // Skip default fields
                    deleteFields.push({"name": 'field.name});
                }
            }

            // Fetch copy fields from solr
            SolrCopyFieldsResponse copyFieldsResponse = check solrClient->/solr/[collection]/schema/copyfields.get();
            SolrCopyField[] copyFields = copyFieldsResponse.copyFields;

            json[] deleteCopyFields = [];
            foreach SolrCopyField copyField in copyFields {
                deleteCopyFields.push({"source": copyField.'source, "dest": [copyField.dest]});
            }

            // Fetch field types from solr
            SolrFieldTypesResponse fieldTypesResponse = check solrClient->/solr/[collection]/schema/fieldtypes.get();
            SolrFieldType[] fieldTypes = fieldTypesResponse.fieldTypes;

            json[] deleteFieldTypes = [];
            foreach SolrFieldType fieldType in fieldTypes {
                if (fieldType.name.includes("bcentral-")) { // Only delete custom field types
                    deleteFieldTypes.push({"name": fieldType.name});
                }
            }

            json deleteSchema = {
                "delete-copy-field": deleteCopyFields,
                "delete-field": deleteFields,
                "delete-field-type": deleteFieldTypes
            };

            // Delete fields
            log:printInfo("Deleting all fields in apache solr collection : " + collection);
            res = check solrClient->/solr/[collection]/schema.post(deleteSchema);
            log:printInfo("Response received from Solr after deleting all fields: " + check res.getTextPayload());

            // Delete collection
            log:printInfo("Deleting collection in apache solr - " + collection);
            res = check solrClient->/solr/admin/collections.get(action = "DELETE", name = collection);
            log:printInfo("Response received from Solr after deleting collection : " + check res.getTextPayload());
        }
    }

    // Create collection
    log:printInfo("Creating new collection in apache solr - " + solrCollection);
    res = check solrClient->/solr/admin/collections.get(
        action = "CREATE", name = solrCollection, numShards = numShards, replicationFactor = replicationFactor, maxShardsPerNode = maxShardsPerNode, collection\.configName = "_default"
    );
    log:printInfo("Response received from Solr after creating new collection: " + check res.getTextPayload());

    // Create symbols collection
    log:printInfo("Creating new collection in apache solr - " + solrSymbolsCollection);
    res = check solrClient->/solr/admin/collections.get(
        action = "CREATE", name = solrSymbolsCollection, numShards = numShards, replicationFactor = replicationFactor, maxShardsPerNode = maxShardsPerNode, collection\.configName = "_default"
    );
    log:printInfo("Response received from Solr after creating new collection: " + check res.getTextPayload());

    // Disable auto-create fields
    log:printInfo("Disabling auto-create fields in apache solr collection : " + solrCollection);
    res = check solrClient->/solr/[solrCollection]/config.post({"set-user-property": {"update.autoCreateFields": "false"}});
    log:printInfo("Response received from Solr after disabling auto-create fields : " + check res.getTextPayload());

    // Add fields
    string schemaPath = solrCreateSchemaPath;
    json addSchema = check io:fileReadJson(schemaPath);
    log:printInfo("Adding new fields to apache solr - " + solrCollection);
    res = check solrClient->/solr/[solrCollection]/schema.post(addSchema);
    log:printInfo("Response received from Solr after adding new fields : " + check res.getTextPayload());

    // Update solrconfig.xml
    json solrConfig = check io:fileReadJson(solrConfigPath);
    res = check solrClient->/solr/[solrCollection]/config.post(solrConfig);
    log:printInfo("Response received from Solr after solr-config update: " + check res.getTextPayload());

    return handleResponse(res, "Response received from Solr after resetting the index: ", "Error occurred while resetting the index: ");
};

# Handle the response from Solr
#
# + response - response from Solr
# + resMsg - message to be logged
# + errMsg - error message to be logged
# + return - error if issue with response, nil otherwise
isolated function handleResponse(http:Response|error response, string resMsg, string errMsg) returns error? {
    if (response is http:Response) {
        log:printInfo(resMsg + check response.getTextPayload());
    } else {
        log:printError(errMsg, response);
        return response;
    }
}
