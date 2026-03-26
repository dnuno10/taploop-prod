/// Clase con validadores y constantes de límites para campos
class FieldValidators {
  FieldValidators._();

  // ─── Límites de caracteres ───────────────────────────────────────────────
  static const int nameMaxLength = 50;
  static const int jobTitleMaxLength = 50;
  static const int bioMaxLength = 100;
  
  // Contacto y Redes
  static const int contactPrimaryMaxLength = 200;    // valor (teléfono, email, etc)
  static const int contactSecondaryMaxLength = 100;  // etiqueta
  static const int socialUrlMaxLength = 200;
  static const int socialLabelMaxLength = 100;
  static const int calendarUrlMaxLength = 200;
  
  // Formularios dinámicos
  static const int dynamicFieldMaxLength = 200;

  // ─── Validadores de formato ──────────────────────────────────────────────

  /// Valida que sea un teléfono (solo dígitos, +, -, espacios)
  static ValidationResult validatePhoneNumber(String value) {
    if (value.isEmpty) {
      return ValidationResult.valid();
    }
    
    final cleanedValue = value.replaceAll(RegExp(r'[^\d+\-\s]'), '');
    if (cleanedValue.isEmpty) {
      return ValidationResult.invalid('Teléfono inválido. Solo se permiten números, +, - y espacios.');
    }
    
    // Debe tener al menos 7 dígitos
    final digitsOnly = cleanedValue.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.length < 7) {
      return ValidationResult.invalid('El teléfono debe tener al menos 7 dígitos.');
    }
    
    return ValidationResult.valid();
  }

  /// Valida que sea un email válido
  static ValidationResult validateEmail(String value) {
    if (value.isEmpty) {
      return ValidationResult.valid();
    }

    final emailRegex = RegExp(
      r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$",
    );

    if (!emailRegex.hasMatch(value)) {
      return ValidationResult.invalid('Ingresa un email válido.');
    }

    return ValidationResult.valid();
  }

  /// Valida que sea una URL válida (http/https)
  static ValidationResult validateUrl(String value) {
    if (value.isEmpty) {
      return ValidationResult.valid();
    }

    try {
      final uri = Uri.parse(value);
      
      // Debe tener esquema http o https
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        return ValidationResult.invalid(
          'La URL debe comenzar con http:// o https://',
        );
      }

      // Debe tener host
      if (uri.host.isEmpty) {
        return ValidationResult.invalid('La URL debe ser válida.');
      }

      return ValidationResult.valid();
    } catch (_) {
      return ValidationResult.invalid('La URL no es válida.');
    }
  }

  /// Valida que solo contenga números (para campos numéricos)
  static ValidationResult validateNumericOnly(String value) {
    if (value.isEmpty) {
      return ValidationResult.valid();
    }

    if (!RegExp(r'^[0-9]+([.,][0-9]+)?$').hasMatch(value)) {
      return ValidationResult.invalid('Solo se permiten números.');
    }

    return ValidationResult.valid();
  }

  /// Valida que sea texto (letras, números, espacios, puntuación básica)
  static ValidationResult validateTextOnly(String value) {
    if (value.isEmpty) {
      return ValidationResult.valid();
    }

    // Permite letras, números, espacios y puntuación común
    final allowedChars = RegExp(r'^[a-zA-Z0-9áéíóúñÁÉÍÓÚÑ\s.,;:!?()\-@]+$');
    if (!allowedChars.hasMatch(value)) {
      return ValidationResult.invalid(
        'Solo se permiten letras, números y puntuación básica.',
      );
    }

    return ValidationResult.valid();
  }

  // ─── Validadores de longitud ─────────────────────────────────────────────

  /// Valida longitud máxima
  static ValidationResult validateMaxLength(String value, int maxLength, String fieldName) {
    if (value.length > maxLength) {
      return ValidationResult.invalid(
        '$fieldName no puede exceder $maxLength caracteres.',
      );
    }
    return ValidationResult.valid();
  }

  /// Valida que el campo no esté vacío
  static ValidationResult validateRequired(String value, String fieldName) {
    if (value.trim().isEmpty) {
      return ValidationResult.invalid('$fieldName es requerido.');
    }
    return ValidationResult.valid();
  }

  // ─── Validadores combinados ──────────────────────────────────────────────

  /// Valida contacto (teléfono/whatsapp)
  static ValidationResult validateContactPhone(String value) {
    if (value.trim().isEmpty) {
      return ValidationResult.valid(); // Opcional
    }
    
    if (value.length > contactPrimaryMaxLength) {
      return ValidationResult.invalid(
        'El teléfono no puede exceder $contactPrimaryMaxLength caracteres.',
      );
    }

    return validatePhoneNumber(value);
  }

  /// Valida contacto (email)
  static ValidationResult validateContactEmail(String value) {
    if (value.trim().isEmpty) {
      return ValidationResult.valid(); // Opcional
    }

    if (value.length > contactPrimaryMaxLength) {
      return ValidationResult.invalid(
        'El email no puede exceder $contactPrimaryMaxLength caracteres.',
      );
    }

    return validateEmail(value);
  }

  /// Valida contacto (website/address)
  static ValidationResult validateContactText(String value) {
    if (value.trim().isEmpty) {
      return ValidationResult.valid(); // Opcional
    }

    if (value.length > contactPrimaryMaxLength) {
      return ValidationResult.invalid(
        'Este campo no puede exceder $contactPrimaryMaxLength caracteres.',
      );
    }

    return ValidationResult.valid();
  }

  /// Valida URL de redes sociales
  static ValidationResult validateSocialUrl(String value) {
    if (value.trim().isEmpty) {
      return ValidationResult.valid(); // Opcional
    }

    if (value.length > socialUrlMaxLength) {
      return ValidationResult.invalid(
        'La URL no puede exceder $socialUrlMaxLength caracteres.',
      );
    }

    return validateUrl(value);
  }

  /// Valida etiqueta de redes sociales
  static ValidationResult validateSocialLabel(String value) {
    if (value.trim().isEmpty) {
      return ValidationResult.valid(); // Opcional
    }

    if (value.length > socialLabelMaxLength) {
      return ValidationResult.invalid(
        'La etiqueta no puede exceder $socialLabelMaxLength caracteres.',
      );
    }

    return ValidationResult.valid();
  }

  /// Valida URL de calendario
  static ValidationResult validateCalendarUrl(String value) {
    if (value.trim().isEmpty) {
      return ValidationResult.valid(); // Opcional
    }

    if (value.length > calendarUrlMaxLength) {
      return ValidationResult.invalid(
        'La URL no puede exceder $calendarUrlMaxLength caracteres.',
      );
    }

    return validateUrl(value);
  }
}

/// Clase que representa el resultado de una validación
class ValidationResult {
  final bool isValid;
  final String? errorMessage;

  ValidationResult.valid()
      : isValid = true,
        errorMessage = null;

  ValidationResult.invalid(this.errorMessage) : isValid = false;

  // Para compatibilidad con forma más corta
  factory ValidationResult(bool valid, {String? error}) {
    return valid ? ValidationResult.valid() : ValidationResult.invalid(error ?? 'Error');
  }
}
