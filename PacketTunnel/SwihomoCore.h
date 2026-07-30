#include <stddef.h>
#include <stdint.h>

int SwihomoCoreStart(
    uint8_t *profile,
    size_t profileLength,
    const char *homeDirectory
);
int SwihomoCoreInputPacket(uint8_t *packet, size_t length, int family);
void SwihomoCoreStop(void);
void SwihomoCoreFreeMemory(void);
char *SwihomoCoreLastError(void);
char *SwihomoCoreExternalResources(void);
char *SwihomoCoreProxyGroupOrder(void);
int SwihomoCoreReadExternalResource(const char *identifier, uint8_t **contents, size_t *length);
int SwihomoCoreWriteExternalResource(const char *identifier, uint8_t *contents, size_t length);
void SwihomoCoreFreeString(char *value);
void SwihomoCoreFreeData(uint8_t *value);
