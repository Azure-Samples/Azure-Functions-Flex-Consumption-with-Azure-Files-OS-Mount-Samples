@description('EventGrid system topic name')
param eventGridTopicName string

@description('Function app URI')
param functionAppUri string

@description('Function app name')
param functionAppName string

@description('Container name to monitor')
param containerName string = 'images-input'

// Reference to the EventGrid system topic
resource eventGridTopic 'Microsoft.EventGrid/systemTopics@2024-06-01-preview' existing = {
  name: eventGridTopicName
}

// EventGrid subscription for blob created events
resource eventGridSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2024-06-01-preview' = {
  name: 'blob-created-subscription'
  parent: eventGridTopic
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: '${functionAppUri}/runtime/webhooks/EventGrid?functionName=process_image_blob&code=${listKeys(resourceId('Microsoft.Web/sites/host', functionAppName, 'default'), '2023-12-01').systemKeys.eventgrid_extension}'
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      subjectBeginsWith: '/blobServices/default/containers/${containerName}/'
    }
    eventDeliverySchema: 'EventGridSchema'
  }
}

output subscriptionName string = eventGridSubscription.name
