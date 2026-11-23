#include <stdio.h>

#include "outils.h"

int main(void)
{
	printf("Bonjour depuis {{NAME}} ! 2 + 3 = %d\n", addition(2, 3));
	return 0;
}
